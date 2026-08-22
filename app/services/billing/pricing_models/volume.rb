module Billing
  module PricingModels
    # Volume pricing: the total quantity picks one tier and every unit is
    # charged at that tier's rate. Buying more can therefore make the whole
    # bill cheaper, which is the point of it.
    class Volume < Base
      include TierList

      def validation_errors = tier_errors

      private

      def compute(quantity)
        billable = billable_units(quantity)
        tier = tiers.find { |candidate| candidate.covers?(billable) } || tiers.last
        return Result.new(amount_cents: 0, breakdown: { "model" => "volume", "quantity" => quantity.to_s("F") }) if tier.nil?

        amount = (billable * tier.unit_amount_cents) + tier.flat_amount_cents

        Result.new(
          amount_cents: to_cents(amount),
          breakdown: {
            "model" => "volume",
            "quantity" => quantity.to_s("F"),
            "free_units" => free_units.to_s("F"),
            "billable_quantity" => billable.to_s("F"),
            "tiers" => [ {
              "from" => "0",
              "up_to" => tier.unbounded? ? nil : tier.up_to.to_s("F"),
              "units" => billable.to_s("F"),
              "unit_amount_cents" => tier.unit_amount_cents.to_s("F"),
              "flat_amount_cents" => tier.flat_amount_cents.to_s("F"),
              "amount_cents" => to_cents(amount)
            } ]
          }
        )
      end
    end
  end
end
