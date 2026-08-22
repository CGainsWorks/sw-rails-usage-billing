module Billing
  # The four pricing shapes a usage charge can take. Each one turns a quantity
  # into an amount in cents plus a breakdown that explains the arithmetic.
  module PricingModels
    NAMES = %w[per_unit package tiered volume].freeze

    Result = Data.define(:amount_cents, :breakdown)

    def self.build(name, properties)
      case name.to_s
      when "per_unit" then PerUnit.new(properties)
      when "package" then Package.new(properties)
      when "tiered" then Tiered.new(properties)
      when "volume" then Volume.new(properties)
      else raise ArgumentError, "unknown pricing model #{name.inspect}"
      end
    end

    def self.human_name(name)
      { "per_unit" => "Per unit", "package" => "Package", "tiered" => "Graduated tiers", "volume" => "Volume" }
        .fetch(name.to_s, name.to_s.humanize)
    end
  end
end
