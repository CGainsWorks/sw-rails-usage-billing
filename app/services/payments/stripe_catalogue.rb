module Payments
  # Translates Meterly's catalogue into Stripe's: a BillableMetric becomes a
  # Billing Meter and a Charge becomes a metered Price backed by that meter.
  #
  # Only shapes Stripe can express exactly are translated. Anything else raises
  # Unsupported rather than publishing a price that would disagree with the
  # invoice Meterly writes. Every method here is pure: it builds request
  # parameters and never calls Stripe.
  module StripeCatalogue
    Unsupported = Class.new(StandardError)

    METER_FORMULAS = { "count" => "count", "sum" => "sum" }.freeze
    INTERVALS = { "monthly" => "month", "yearly" => "year" }.freeze
    CUSTOMER_KEY = "stripe_customer_id".freeze
    VALUE_KEY = "value".freeze

    module_function

    # Stripe meter event names are unique per Stripe account, while metric codes
    # are only unique per organization, so the organization is part of the name.
    def event_name(metric) = "meterly_#{metric.organization_id}_#{metric.code}"

    def meter_params(metric)
      formula = METER_FORMULAS[metric.aggregation_type]
      if formula.nil?
        raise Unsupported, "Stripe meters cannot aggregate #{metric.aggregation_type} (#{metric.code})"
      end
      raise Unsupported, "Stripe meters cannot filter on event properties (#{metric.code})" if metric.filters_hash.any?

      {
        display_name: metric.name,
        event_name: event_name(metric),
        default_aggregation: { formula: formula },
        customer_mapping: { type: "by_id", event_payload_key: CUSTOMER_KEY },
        value_settings: { event_payload_key: VALUE_KEY }
      }
    end

    # The value a meter event carries for one usage event, or nil when the event
    # would not count, mirroring the Aggregator, which skips non-numeric values.
    def meter_value(metric, event)
      return "1" if metric.aggregation_type == "count"

      raw = event.properties[metric.property_name].to_s.strip
      return nil unless raw.match?(/\A-?\d+(\.\d+)?\z/)

      BigDecimal(raw).to_s("F").delete_suffix(".0")
    end

    def product_params(plan)
      { name: plan.name, metadata: { meterly_plan_id: plan.id.to_s, meterly_plan_code: plan.code } }
    end

    def price_params(charge, meter_id:, product_id:)
      plan = charge.plan
      {
        currency: plan.currency.downcase,
        product: product_id,
        nickname: charge.display_name,
        recurring: { interval: INTERVALS.fetch(plan.interval), usage_type: "metered", meter: meter_id },
        metadata: { meterly_charge_id: charge.id.to_s, meterly_metric_code: charge.billable_metric.code }
      }.merge(pricing_params(charge))
    end

    def pricing_params(charge)
      properties = charge.properties.deep_stringify_keys
      free = decimal(properties["free_units"])

      case charge.pricing_model
      when "per_unit" then per_unit(properties, free)
      when "tiered" then graduated(properties, free)
      when "volume" then volume(properties, free)
      when "package" then package(properties, free)
      else raise Unsupported, "unknown pricing model #{charge.pricing_model.inspect}"
      end
    end

    def per_unit(properties, free)
      unit = amount(properties["unit_amount_cents"])
      return { billing_scheme: "per_unit", unit_amount_decimal: unit } if free.zero?

      # A free allowance is a first tier that costs nothing.
      {
        billing_scheme: "tiered",
        tiers_mode: "graduated",
        tiers: [ { up_to: whole(free, "free_units"), unit_amount_decimal: "0" },
                 { up_to: "inf", unit_amount_decimal: unit } ]
      }
    end

    # Meterly slices billable units (usage less the allowance) into tiers, so
    # each Stripe boundary moves up by the allowance and the allowance becomes
    # a free first tier.
    def graduated(properties, free)
      tiers = Array(properties["tiers"]).map(&:deep_stringify_keys)
      stripe_tiers = tiers.map do |tier|
        bound = tier["up_to"].presence
        {
          up_to: bound.nil? ? "inf" : whole(decimal(bound) + free, "tier up_to"),
          unit_amount_decimal: amount(tier["unit_amount_cents"]),
          flat_amount_decimal: amount(tier["flat_amount_cents"] || 0)
        }
      end
      stripe_tiers.unshift({ up_to: whole(free, "free_units"), unit_amount_decimal: "0" }) if free.positive?

      { billing_scheme: "tiered", tiers_mode: "graduated", tiers: stripe_tiers }
    end

    def volume(properties, free)
      raise Unsupported, "Stripe volume prices have no free allowance" if free.positive?

      tiers = Array(properties["tiers"]).map(&:deep_stringify_keys).map do |tier|
        bound = tier["up_to"].presence
        {
          up_to: bound.nil? ? "inf" : whole(decimal(bound), "tier up_to"),
          unit_amount_decimal: amount(tier["unit_amount_cents"]),
          flat_amount_decimal: amount(tier["flat_amount_cents"] || 0)
        }
      end

      { billing_scheme: "tiered", tiers_mode: "volume", tiers: tiers }
    end

    # A part-used package costs a whole one: Stripe divides the quantity and
    # rounds up, which is the same rule.
    def package(properties, free)
      raise Unsupported, "Stripe package prices have no free allowance" if free.positive?

      {
        billing_scheme: "per_unit",
        unit_amount_decimal: amount(properties["package_amount_cents"]),
        transform_quantity: { divide_by: whole(decimal(properties["package_size"]), "package_size"), round: "up" }
      }
    end

    def decimal(value)
      return BigDecimal(0) if value.nil? || value.to_s.strip.empty?

      BigDecimal(value.to_s)
    end

    # Stripe takes sub-cent unit prices as a decimal string in the minor unit,
    # which is exactly how Meterly stores them.
    def amount(value) = decimal(value).to_s("F").delete_suffix(".0")

    def whole(value, label)
      raise Unsupported, "Stripe needs a whole number for #{label}, got #{value.to_s('F')}" unless value.frac.zero?

      value.to_i
    end
  end
end
