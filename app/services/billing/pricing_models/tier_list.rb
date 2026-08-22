module Billing
  module PricingModels
    # Shared tier parsing for the graduated and volume models. A tier is
    #   { "up_to" => 10_000, "unit_amount_cents" => "0.5", "flat_amount_cents" => 0 }
    # and the final tier must leave up_to empty, meaning "and everything above".
    module TierList
      Tier = Data.define(:up_to, :unit_amount_cents, :flat_amount_cents) do
        def unbounded? = up_to.nil?

        def covers?(quantity) = unbounded? || quantity <= up_to
      end

      INFINITY = BigDecimal("Infinity")

      private

      def tiers
        @tiers ||= Array(properties["tiers"]).map do |tier|
          tier = tier.deep_stringify_keys
          up_to = tier["up_to"].presence
          Tier.new(
            up_to: up_to.nil? ? nil : decimalize(up_to),
            unit_amount_cents: decimalize(tier["unit_amount_cents"]),
            flat_amount_cents: decimalize(tier["flat_amount_cents"] || 0)
          )
        end
      end

      def tier_errors
        raw = properties["tiers"]
        return [ "tiers must be a non-empty list" ] unless raw.is_a?(Array) && raw.any?

        errors = []
        errors << "the last tier must have an empty up_to" unless tiers.last.unbounded?
        errors << "only the last tier may have an empty up_to" if tiers[0...-1].any?(&:unbounded?)

        bounds = tiers[0...-1].map(&:up_to)
        errors << "tier boundaries must increase" if bounds != bounds.sort || bounds.uniq != bounds
        errors << "tier boundaries must be greater than zero" if bounds.any? { |bound| bound <= 0 }
        errors << "tier unit amounts cannot be negative" if tiers.any? { |tier| tier.unit_amount_cents.negative? }

        errors
      end

      def tier_upper_bound(tier) = tier.unbounded? ? INFINITY : tier.up_to
    end
  end
end
