module Billing
  module PricingModels
    # Usage is sold in blocks and a part-used block costs a whole block.
    # Properties:
    #   package_size:         1_000
    #   package_amount_cents: 500
    #   free_units:           0
    class Package < Base
      def validation_errors
        errors = []
        errors << "package_size must be greater than zero" unless positive_number?("package_size")
        errors << "package_amount_cents must be a number of zero or more" unless non_negative_number?("package_amount_cents")
        errors
      end

      private

      def compute(quantity)
        size = decimal("package_size", default: 1)
        size = BigDecimal(1) unless size.positive?

        billable = billable_units(quantity)
        packages = (billable / size).ceil
        amount = packages * decimal("package_amount_cents")

        Result.new(
          amount_cents: to_cents(amount),
          breakdown: {
            "model" => "package",
            "quantity" => quantity.to_s("F"),
            "free_units" => free_units.to_s("F"),
            "billable_quantity" => billable.to_s("F"),
            "package_size" => size.to_s("F"),
            "packages" => packages.to_i,
            "package_amount_cents" => decimal("package_amount_cents").to_s("F")
          }
        )
      end
    end
  end
end
