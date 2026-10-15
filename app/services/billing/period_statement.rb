module Billing
  # Everything a subscription owes for one period, computed from the plan and
  # the events and nothing else. Invoicing persists a statement; the usage
  # preview in the dashboard and the API renders the very same object for the
  # period still in progress, so what a customer is quoted mid-month is what
  # the invoice will say.
  class PeriodStatement
    Line = Data.define(:kind, :description, :quantity, :unit_amount_cents, :amount_cents, :breakdown, :charge, :billable_metric)

    Statement = Data.define(:subscription, :period, :currency, :lines, :subtotal_cents, :tax_rate_bps, :tax_cents, :total_cents) do
      def usage_lines = lines.select { |line| line.kind == "usage" }

      def to_h
        {
          period_start: period.starts_at, period_end: period.ends_at, currency: currency,
          subtotal_cents: subtotal_cents, tax_cents: tax_cents, total_cents: total_cents
        }
      end
    end

    def self.call(...) = new(...).call

    def initialize(subscription:, period:)
      @subscription = subscription
      @period = period
    end

    def call
      lines = [ subscription_fee_line, *usage_lines ].compact
      subtotal = lines.sum(&:amount_cents)

      if (true_up = minimum_true_up_line(subtotal))
        lines << true_up
        subtotal += true_up.amount_cents
      end

      tax_rate_bps = subscription.customer.tax_rate_bps
      tax_cents = ((BigDecimal(subtotal) * tax_rate_bps) / 10_000).round(0, BigDecimal::ROUND_HALF_UP).to_i

      Statement.new(
        subscription: subscription, period: period, currency: subscription.plan.currency,
        lines: lines, subtotal_cents: subtotal, tax_rate_bps: tax_rate_bps,
        tax_cents: tax_cents, total_cents: subtotal + tax_cents
      )
    end

    private

    attr_reader :subscription, :period

    def plan = subscription.plan

    def subscription_fee_line
      return nil if plan.base_amount_cents.zero?

      fraction = period.proration_fraction
      amount = (BigDecimal(plan.base_amount_cents) * fraction).round(0, BigDecimal::ROUND_HALF_UP).to_i

      Line.new(
        kind: "subscription_fee",
        description: "#{plan.name} subscription",
        quantity: BigDecimal(1),
        unit_amount_cents: amount,
        amount_cents: amount,
        breakdown: {
          "full_amount_cents" => plan.base_amount_cents,
          "prorated" => period.truncated?,
          "proration_fraction" => fraction.round(6).to_s("F"),
          "period_start" => period.starts_at.utc.iso8601,
          "period_end" => period.ends_at.utc.iso8601
        }.compact,
        charge: nil,
        billable_metric: nil
      )
    end

    def usage_lines
      plan.charges.includes(:billable_metric).sort_by { |charge| charge.billable_metric.code }.filter_map do |charge|
        calculated = ChargeCalculator.call(subscription: subscription, charge: charge, period: period)
        next if calculated.quantity.zero? && calculated.amount_cents.zero?

        Line.new(
          kind: "usage",
          description: calculated.description,
          quantity: calculated.quantity,
          unit_amount_cents: nil,
          amount_cents: calculated.amount_cents,
          breakdown: calculated.breakdown,
          charge: charge,
          billable_metric: calculated.billable_metric
        )
      end
    end

    # A committed spend floor: the customer pays at least this much and usage
    # eats into the commitment rather than adding to it.
    def minimum_true_up_line(subtotal)
      minimum = (BigDecimal(plan.minimum_amount_cents) * period.proration_fraction).round(0, BigDecimal::ROUND_HALF_UP).to_i
      return nil if minimum.zero? || subtotal >= minimum

      Line.new(
        kind: "minimum_true_up",
        description: "Minimum commitment true-up",
        quantity: BigDecimal(1),
        unit_amount_cents: minimum - subtotal,
        amount_cents: minimum - subtotal,
        breakdown: { "minimum_amount_cents" => minimum, "charged_before_true_up_cents" => subtotal },
        charge: nil,
        billable_metric: nil
      )
    end
  end
end
