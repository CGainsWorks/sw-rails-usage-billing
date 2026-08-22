module Billing
  # One charge, one period: aggregate the usage, price it, and describe the
  # result the way it will appear on an invoice.
  class ChargeCalculator
    Line = Data.define(:charge, :billable_metric, :quantity, :amount_cents, :breakdown) do
      def description = charge.display_name

      def unit_amount_cents
        return nil if quantity.zero?

        (BigDecimal(amount_cents) / quantity).round(4)
      end
    end

    def self.call(...) = new(...).call

    def initialize(subscription:, charge:, period:)
      @subscription = subscription
      @charge = charge
      @period = period
    end

    def call
      metric = charge.billable_metric
      quantity = Aggregator.call(subscription: subscription, metric: metric, period: period)
      result = charge.pricing.call(quantity)

      Line.new(
        charge: charge,
        billable_metric: metric,
        quantity: quantity,
        amount_cents: result.amount_cents,
        breakdown: result.breakdown.merge("aggregation" => metric.aggregation_type)
      )
    end

    private

    attr_reader :subscription, :charge, :period
  end
end
