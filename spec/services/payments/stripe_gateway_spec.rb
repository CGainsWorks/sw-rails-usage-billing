require "rails_helper"

# Runs the real gateway, through the official stripe gem, against stripe-mock.
# See spec/support/stripe_mock.rb.
RSpec.describe Payments::StripeGateway, :stripe_mock do
  subject(:gateway) { described_class.new(client: client) }

  let(:client) { stripe_mock_client }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization, name: "Bramble Ltd", email: "billing@bramble.test") }
  let(:metric) { create(:billable_metric, organization: organization, code: "llm_tokens", aggregation_type: "sum", property_name: "tokens") }
  let(:plan) { create(:plan, organization: organization, base_amount_cents: 10_000) }
  let(:subscription) { create(:subscription, organization: organization, customer: customer, plan: plan) }
  let(:invoice) do
    Invoice.create!(organization: organization, customer: customer, subscription: subscription,
                    status: "finalized", number: "INV-TEST-2026-00001", currency: "GBP",
                    period_start: 1.month.ago, period_end: Time.current, finalized_at: Time.current,
                    subtotal_cents: 10_540, tax_rate_bps: 2_000, tax_cents: 2_108, total_cents: 12_648).tap do |created|
      created.line_items.create!(kind: "subscription_fee", description: "Plan subscription", amount_cents: 10_000, position: 0)
      created.line_items.create!(kind: "usage", description: "LLM tokens", amount_cents: 540, position: 1)
    end
  end

  def reference(record, kind) = ProviderReference.external_id_for(provider: "stripe", record: record, kind: kind)

  describe "#sync_customer" do
    it "creates the Stripe customer once and remembers it" do
      first = gateway.sync_customer(customer)
      second = gateway.sync_customer(customer)

      expect(first).to start_with("cus_")
      expect(second).to eq(first)
      expect(ProviderReference.where(record: customer, kind: "customer").count).to eq(1)
    end

    it "sends an idempotency key so a retried request cannot make a second customer" do
      allow(client.v1.customers).to receive(:create).and_call_original

      gateway.sync_customer(customer)

      expect(client.v1.customers).to have_received(:create)
        .with(hash_including(name: "Bramble Ltd", email: "billing@bramble.test"), { idempotency_key: "meterly-customer-#{customer.id}" })
    end
  end

  describe "#charge" do
    it "mirrors the invoice line for line, finalises it and pays it" do
      amounts = []
      allow(client.v1.invoice_items).to receive(:create).and_wrap_original do |original, params, opts|
        amounts << params[:amount]
        original.call(params, opts)
      end

      result = gateway.charge(invoice)

      expect(result).to be_success
      expect(result.reference).to start_with("in_")
      expect(reference(invoice, "invoice")).to eq(result.reference)
      expect(amounts).to contain_exactly(10_000, 540, 2_108)
      expect(amounts.sum).to eq(invoice.total_cents)
    end

    it "pays the same Stripe invoice again on a retry rather than making a new one" do
      first = gateway.charge(invoice)
      allow(client.v1.invoices).to receive(:create).and_call_original

      second = gateway.charge(invoice)

      expect(second.reference).to eq(first.reference)
      expect(client.v1.invoices).not_to have_received(:create)
    end

    it "reports a declined card as a failed result, not an exception" do
      allow(client.v1.invoices).to receive(:pay)
        .and_raise(Stripe::CardError.new("Your card was declined.", nil, code: "card_declined", http_status: 402))

      result = gateway.charge(invoice)

      expect(result).not_to be_success
      expect(result.failure_reason).to eq("card_declined")
      expect(result.reference).to start_with("in_")
    end

    it "turns an outage into a transient error the job retries on" do
      allow(client.v1.invoices).to receive(:pay).and_raise(Stripe::APIConnectionError.new("connection refused"))

      expect { gateway.charge(invoice) }.to raise_error(Payments::Gateway::TransientError, /connection refused/)
    end

    it "refuses an invoice whose lines do not add up to its total" do
      invoice.update_columns(total_cents: 99_999)

      expect { gateway.charge(invoice) }.to raise_error(ArgumentError, /not 99999/)
    end

    it "collects through Payments::Collect and marks the invoice paid" do
      attempt = Payments::Collect.call(invoice: invoice, gateway: gateway)

      expect(attempt).to be_succeeded
      expect(attempt.provider).to eq("stripe")
      expect(invoice.reload).to be_paid
    end
  end

  describe "#sync_catalogue" do
    it "publishes a product, a meter and a metered price for each charge Stripe can express" do
      supported = create(:charge, plan: plan, billable_metric: metric, pricing_model: "tiered",
                                  properties: { "tiers" => [ { "up_to" => 1_000_000, "unit_amount_cents" => "0.002" },
                                                             { "up_to" => nil, "unit_amount_cents" => "0.001" } ] })
      unique = create(:billable_metric, organization: organization, code: "seats", aggregation_type: "unique_count", property_name: "user")
      unsupported = create(:charge, plan: plan, billable_metric: unique, pricing_model: "per_unit", properties: { "unit_amount_cents" => 500 })

      result = gateway.sync_catalogue(plan)

      expect(result.product_id).to start_with("prod_")
      expect(result.prices.keys).to eq([ supported.id ])
      expect(result.skipped.keys).to eq([ unsupported.id ])
      expect(reference(metric, "meter")).to be_present
      expect(reference(unique, "meter")).to be_nil
    end
  end

  describe "#report_usage" do
    let(:event) do
      create(:usage_event, subscription: subscription, code: "llm_tokens", transaction_id: "req-42",
                           occurred_at: 1.hour.ago, properties: { "tokens" => "1834" })
    end

    it "sends a meter event once the metric has a meter" do
      create(:charge, plan: plan, billable_metric: metric, pricing_model: "per_unit", properties: { "unit_amount_cents" => "0.002" })
      gateway.sync_catalogue(plan)
      allow(client.v1.billing.meter_events).to receive(:create).and_call_original

      expect(gateway.report_usage(event).object).to eq("billing.meter_event")
      expect(client.v1.billing.meter_events).to have_received(:create).with(
        hash_including(event_name: "meterly_#{organization.id}_llm_tokens", identifier: "meterly-#{organization.id}-req-42",
                       payload: { "stripe_customer_id" => reference(customer, "customer"), "value" => "1834" }),
        anything
      )
    end

    it "does nothing for a metric that was never published" do
      expect(gateway.report_usage(event)).to be_nil
    end
  end
end
