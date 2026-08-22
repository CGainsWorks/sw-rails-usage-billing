module Billing
  # Writes a draft invoice for one closed period.
  #
  # Idempotent by construction: a unique index on (subscription_id,
  # period_start) means a job that runs twice, or two workers that pick up the
  # same subscription, produce one invoice and not two.
  class GenerateInvoice
    def self.call(...) = new(...).call

    def initialize(subscription:, period:)
      @subscription = subscription
      @period = period
    end

    def call
      existing = find_existing
      return existing if existing

      create_invoice
    rescue ActiveRecord::RecordNotUnique
      find_existing || raise
    end

    private

    attr_reader :subscription, :period

    def find_existing
      Invoice.find_by(subscription_id: subscription.id, period_start: period.starts_at)
    end

    def create_invoice
      statement = PeriodStatement.call(subscription: subscription, period: period)

      Invoice.transaction do
        invoice = Invoice.create!(
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          status: "draft",
          currency: statement.currency,
          period_start: period.starts_at,
          period_end: period.ends_at,
          tax_rate_bps: statement.tax_rate_bps,
          subtotal_cents: statement.subtotal_cents,
          tax_cents: statement.tax_cents,
          total_cents: statement.total_cents,
          metadata: { "plan_code" => subscription.plan.code, "prorated" => period.truncated? }
        )

        statement.lines.each_with_index do |line, index|
          invoice.line_items.create!(
            charge: line.charge,
            billable_metric: line.billable_metric,
            kind: line.kind,
            description: line.description,
            quantity: line.quantity,
            unit_amount_cents: line.unit_amount_cents,
            amount_cents: line.amount_cents,
            breakdown: line.breakdown,
            position: index
          )
        end

        invoice
      end
    end
  end
end
