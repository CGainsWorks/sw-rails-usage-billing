module Billing
  module PricingModels
    # Every billable unit costs the same. Properties:
    #   unit_amount_cents: "0.25"   (fractions of a cent are allowed)
    #   free_units:        1_000    (optional allowance)
    class PerUnit < Base
      def validation_errors
        errors = []
        errors << "unit_amount_cents must be a number of zero or more" unless non_negative_number?("unit_amount_cents")
        errors << "free_units cannot be negative" if properties["free_units"].present? && free_units.negative?
        errors
      end

      private

      def compute(quantity)
        billable = billable_units(quantity)
        amount = billable * decimal("unit_amount_cents")

        Result.new(
          amount_cents: to_cents(amount),
          breakdown: {
            "model" => "per_unit",
            "quantity" => quantity.to_s("F"),
            "free_units" => free_units.to_s("F"),
            "billable_quantity" => billable.to_s("F"),
            "unit_amount_cents" => decimal("unit_amount_cents").to_s("F")
          }
        )
      end
    end
  end
end
