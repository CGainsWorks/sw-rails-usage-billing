module Billing
  module PricingModels
    class Base
      # Money is held as BigDecimal cents for the whole calculation and rounded
      # once, at the end. Rounding each tier separately would let a customer
      # billed in ten tiers lose or gain half a penny ten times over.
      ROUNDING = BigDecimal::ROUND_HALF_UP

      attr_reader :properties

      def initialize(properties = {})
        @properties = (properties || {}).deep_stringify_keys
      end

      # @param quantity [BigDecimal, Numeric] the aggregated usage
      # @return [Result]
      def call(quantity)
        quantity = decimalize(quantity)
        raise ArgumentError, "quantity cannot be negative" if quantity.negative?

        compute(quantity)
      end

      # Messages describing why these properties cannot price anything, used by
      # the Charge model so a broken price never reaches an invoice.
      def validation_errors = []

      private

      def compute(_quantity) = raise(NotImplementedError)

      def free_units = decimal("free_units")

      def billable_units(quantity) = [ quantity - free_units, BigDecimal(0) ].max

      def decimal(key, default: 0)
        value = properties[key.to_s]
        return BigDecimal(default.to_s) if value.nil? || value.to_s.strip.empty?

        decimalize(value)
      end

      def decimalize(value)
        case value
        when BigDecimal then value
        when Integer then BigDecimal(value)
        when Float then BigDecimal(value.to_s)
        else BigDecimal(value.to_s)
        end
      rescue ArgumentError
        BigDecimal(0)
      end

      def to_cents(amount) = amount.round(0, ROUNDING).to_i

      def positive_number?(key)
        value = properties[key.to_s]
        value.present? && decimalize(value).positive?
      end

      def non_negative_number?(key)
        value = properties[key.to_s]
        value.present? && !decimalize(value).negative?
      end
    end
  end
end
