module Payments
  # Collects Meterly invoices through Stripe with the official stripe gem.
  #
  # Meterly stays the rating engine of record. When an invoice is charged, the
  # rated invoice is mirrored into Stripe line for line as invoice items on a
  # Stripe invoice, which is then finalised and paid. Stripe therefore never
  # re-rates usage and the two totals cannot drift apart.
  #
  # It can also publish the catalogue (a Billing Meter per metric and a metered
  # Price per charge) and mirror usage as meter events, so the same plan and
  # usage are visible in Stripe-hosted surfaces. Those prices are never attached
  # to a Stripe subscription, so nothing is billed twice.
  #
  # Every write carries an idempotency key derived from Meterly ids, so a job
  # that is retried after a timeout cannot create a second customer, invoice or
  # charge.
  class StripeGateway
    PROVIDER = "stripe".freeze

    # Stripe only accepts meter events from the last 35 days.
    METER_EVENT_WINDOW = 35.days

    TRANSIENT_ERRORS = [ Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError ].freeze

    CatalogueResult = Data.define(:product_id, :prices, :skipped)

    # STRIPE_API_KEY is a secret key (sk_test_... in test mode). STRIPE_API_BASE
    # points the client somewhere other than api.stripe.com, which is how CI
    # aims it at stripe-mock.
    def self.from_env
      new(client: Stripe::StripeClient.new(ENV.fetch("STRIPE_API_KEY"), api_base: ENV["STRIPE_API_BASE"].presence))
    end

    def initialize(client:)
      @client = client
    end

    def provider = PROVIDER

    # @return [String] the Stripe customer id, created on first use
    def sync_customer(customer)
      remembered(customer, "customer") do
        client.v1.customers.create(
          {
            name: customer.name,
            email: customer.email,
            metadata: { meterly_customer_id: customer.id.to_s, meterly_external_id: customer.external_id }
          }.compact,
          idempotency("customer-#{customer.id}")
        )
      end
    end

    # Publishes one plan: a Product for the plan, then a Billing Meter and a
    # metered Price for every charge Stripe can express exactly.
    def sync_catalogue(plan)
      product_id = remembered(plan, "product") do
        client.v1.products.create(StripeCatalogue.product_params(plan), idempotency("product-#{plan.id}"))
      end

      prices = {}
      skipped = {}
      plan.charges.includes(:billable_metric).find_each do |charge|
        prices[charge.id] = sync_price(charge, product_id: product_id)
      rescue StripeCatalogue::Unsupported => e
        skipped[charge.id] = e.message
      end

      CatalogueResult.new(product_id: product_id, prices: prices, skipped: skipped)
    end

    # Copies one accepted usage event to the metric's Stripe meter. Stripe
    # deduplicates on the identifier, which is built from the transaction id, so
    # a replay is as harmless there as it is in Meterly.
    #
    # @return [Stripe::Billing::MeterEvent, nil] nil when the metric has no meter
    #   or the event would not count
    def report_usage(event)
      return nil if event.occurred_at < METER_EVENT_WINDOW.ago

      metric = event.organization.billable_metrics.find_by(code: event.code)
      return nil if metric.nil? || ProviderReference.external_id_for(provider: PROVIDER, record: metric, kind: "meter").nil?

      value = StripeCatalogue.meter_value(metric, event)
      return nil if value.nil?

      customer_id = sync_customer(event.subscription.customer)
      call_stripe do
        client.v1.billing.meter_events.create(
          {
            event_name: StripeCatalogue.event_name(metric),
            identifier: "meterly-#{event.organization_id}-#{event.transaction_id}",
            timestamp: event.occurred_at.to_i,
            payload: { StripeCatalogue::CUSTOMER_KEY => customer_id, StripeCatalogue::VALUE_KEY => value }
          },
          idempotency("meter-event-#{event.id}")
        )
      end
    end

    # Same contract as SimulatedGateway#charge. A declined card is a result,
    # not an exception; an outage raises Gateway::TransientError so the job
    # retries with the same idempotency keys.
    def charge(invoice)
      if invoice.total_cents.zero?
        return Gateway::Result.new(success: true, reference: "stripe_zero_#{invoice.id}", failure_reason: nil)
      end

      stripe_invoice_id = mirror_invoice(invoice)
      call_stripe do
        client.v1.invoices.pay(stripe_invoice_id, {}, idempotency("invoice-#{invoice.id}-pay-#{invoice.payment_attempts.count + 1}"))
      end
      Gateway::Result.new(success: true, reference: stripe_invoice_id, failure_reason: nil)
    rescue Stripe::CardError => e
      Gateway::Result.new(success: false, reference: stripe_invoice_id, failure_reason: e.code.presence || "card_error")
    end

    private

    attr_reader :client

    def sync_price(charge, product_id:)
      meter_params = StripeCatalogue.meter_params(charge.billable_metric)
      price_params = ->(meter_id) { StripeCatalogue.price_params(charge, meter_id: meter_id, product_id: product_id) }
      # Translate before writing anything, so an unsupported charge leaves no
      # orphaned meter behind.
      price_params.call("pending")

      meter_id = remembered(charge.billable_metric, "meter") do
        client.v1.billing.meters.create(meter_params, idempotency("meter-#{charge.billable_metric.id}"))
      end
      remembered(charge, "price") do
        client.v1.prices.create(price_params.call(meter_id), idempotency("price-#{charge.id}"))
      end
    end

    # Creates the Stripe invoice, one invoice item per Meterly line plus the
    # tax and finalises it. The reference is stored only once the whole
    # sequence has succeeded; until then a retry replays the same idempotency
    # keys and Stripe answers with the objects it already made.
    def mirror_invoice(invoice)
      assert_adds_up!(invoice)
      customer_id = sync_customer(invoice.customer)

      remembered(invoice, "invoice") do
        currency = invoice.currency.downcase
        stripe_invoice = client.v1.invoices.create(
          {
            customer: customer_id,
            currency: currency,
            collection_method: "charge_automatically",
            auto_advance: false,
            pending_invoice_items_behavior: "exclude",
            description: "Meterly invoice #{invoice.number}",
            metadata: { meterly_invoice_id: invoice.id.to_s, meterly_invoice_number: invoice.number.to_s }
          },
          idempotency("invoice-#{invoice.id}")
        )

        invoice_items(invoice).each do |key, description, amount_cents|
          client.v1.invoice_items.create(
            { customer: customer_id, invoice: stripe_invoice.id, currency: currency,
              amount: amount_cents, description: description },
            idempotency("invoice-#{invoice.id}-#{key}")
          )
        end

        client.v1.invoices.finalize_invoice(stripe_invoice.id, { auto_advance: false },
                                            idempotency("invoice-#{invoice.id}-finalize"))
        stripe_invoice
      end
    end

    def invoice_items(invoice)
      items = invoice.line_items.reject { |line| line.amount_cents.zero? }
                     .map { |line| [ "line-#{line.id}", line.description, line.amount_cents ] }
      unless invoice.tax_cents.zero?
        items << [ "tax", "Tax at #{(invoice.tax_rate_bps / 100.0).round(2)}%", invoice.tax_cents ]
      end
      items
    end

    # Stripe totals the items itself. If they would not add up to the Meterly
    # total, refuse rather than charge an amount nobody calculated.
    def assert_adds_up!(invoice)
      mirrored = invoice.line_items.sum(&:amount_cents) + invoice.tax_cents
      return if mirrored == invoice.total_cents

      raise ArgumentError, "invoice #{invoice.number} lines and tax total #{mirrored}, not #{invoice.total_cents}"
    end

    # Returns the stored Stripe id for the record and kind, or runs the block,
    # stores the id of the object it returns and returns that id.
    def remembered(record, kind)
      existing = ProviderReference.external_id_for(provider: PROVIDER, record: record, kind: kind)
      return existing if existing

      stripe_object = call_stripe { yield }
      ProviderReference.create!(provider: PROVIDER, record: record, kind: kind, external_id: stripe_object.id)
      stripe_object.id
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Another worker stored it first. The idempotency key meant Stripe handed
      # both of them the same object, so theirs is as good as ours.
      ProviderReference.external_id_for(provider: PROVIDER, record: record, kind: kind) || raise
    end

    def call_stripe
      yield
    rescue *TRANSIENT_ERRORS => e
      raise Gateway::TransientError, "#{e.class.name}: #{e.message}"
    end

    def idempotency(key) = { idempotency_key: "meterly-#{key}" }
  end
end
