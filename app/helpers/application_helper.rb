module ApplicationHelper
  CURRENCY_SYMBOLS = { "GBP" => "£", "EUR" => "€", "USD" => "$" }.freeze

  # Amounts are stored in the smallest unit of the currency, so formatting is
  # the only place a division by 100 is allowed to happen.
  def money(cents, currency = current_organization&.currency || "GBP")
    symbol = CURRENCY_SYMBOLS.fetch(currency.to_s.upcase, "#{currency} ")
    "#{symbol}#{number_with_delimiter(format('%.2f', cents.to_i / 100.0))}"
  end

  # Sub-cent unit prices are real (0.05p per API call), so show more places
  # when the number needs them.
  def unit_money(cents, currency = current_organization&.currency || "GBP")
    symbol = CURRENCY_SYMBOLS.fetch(currency.to_s.upcase, "#{currency} ")
    decimal = BigDecimal(cents.to_s) / 100
    places = decimal.frac.zero? ? 2 : [ decimal.to_s("F").split(".").last.length, 6 ].min
    "#{symbol}#{format("%.#{places}f", decimal)}"
  end

  def quantity(value)
    decimal = BigDecimal(value.to_s)
    decimal.frac.zero? ? number_with_delimiter(decimal.to_i) : number_with_delimiter(decimal.round(4).to_s("F"))
  end

  def period_label(starts_at, ends_at)
    finish = ends_at - 1.second
    if starts_at.year == finish.year
      "#{starts_at.strftime('%-d %b')} to #{finish.strftime('%-d %b %Y')}"
    else
      "#{starts_at.strftime('%-d %b %Y')} to #{finish.strftime('%-d %b %Y')}"
    end
  end

  def status_badge(status)
    tag.span(status.humanize, class: "badge badge--#{status}")
  end

  def charge_pricing_summary(charge)
    properties = charge.properties.deep_stringify_keys
    currency = charge.plan.currency

    case charge.pricing_model
    when "per_unit"
      "#{unit_money(properties['unit_amount_cents'], currency)} per unit#{free_units_suffix(properties)}"
    when "package"
      "#{money(properties['package_amount_cents'].to_i, currency)} per #{quantity(properties['package_size'])} units#{free_units_suffix(properties)}"
    when "tiered", "volume"
      tiers = Array(properties["tiers"])
      "#{tiers.length} #{'tier'.pluralize(tiers.length)}, from #{unit_money(tiers.first&.dig('unit_amount_cents'), currency)} per unit"
    else
      charge.pricing_model.humanize
    end
  end

  def tier_bound_label(tier)
    upper = tier["up_to"]
    from = quantity(tier["from"] || 0)
    upper.present? ? "#{from} to #{quantity(upper)}" : "#{from} and above"
  end

  private

  def free_units_suffix(properties)
    free = properties["free_units"].to_i
    free.positive? ? ", first #{number_with_delimiter(free)} free" : ""
  end
end
