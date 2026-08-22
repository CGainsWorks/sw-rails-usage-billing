module Billing
  module PricingModels
    # Graduated tiers: usage is sliced at the tier boundaries and each slice is
    # charged at its own rate, the way income tax brackets work. 12,000 units
    # against tiers of 10,000 at 0.5c then unlimited at 0.3c costs
    # 10,000 * 0.5c + 2,000 * 0.3c.
    class Tiered < Base
      include TierList

      def validation_errors = tier_errors

      private

      def compute(quantity)
        billable = billable_units(quantity)
        lower = BigDecimal(0)
        amount = BigDecimal(0)
        rows = []

        tiers.each do |tier|
          upper = tier_upper_bound(tier)
          units = [ [ billable, upper ].min - lower, BigDecimal(0) ].max
          break if units.zero? && lower >= billable

          if units.positive?
            tier_amount = (units * tier.unit_amount_cents) + tier.flat_amount_cents
            amount += tier_amount
            rows << {
              "from" => lower.to_s("F"),
              "up_to" => tier.unbounded? ? nil : tier.up_to.to_s("F"),
              "units" => units.to_s("F"),
              "unit_amount_cents" => tier.unit_amount_cents.to_s("F"),
              "flat_amount_cents" => tier.flat_amount_cents.to_s("F"),
              "amount_cents" => tier_amount.round(0, ROUNDING).to_i
            }
          end

          lower = upper
        end

        Result.new(
          amount_cents: to_cents(amount),
          breakdown: {
            "model" => "tiered",
            "quantity" => quantity.to_s("F"),
            "free_units" => free_units.to_s("F"),
            "billable_quantity" => billable.to_s("F"),
            "tiers" => rows
          }
        )
      end
    end
  end
end
