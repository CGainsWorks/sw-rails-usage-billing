require "rails_helper"

RSpec.describe Payments::StripeCatalogue do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization: organization, currency: "GBP", interval: "monthly") }
  let(:metric) { create(:billable_metric, organization: organization, code: "api_calls", aggregation_type: "count") }

  def charge_with(pricing_model, properties)
    build(:charge, plan: plan, billable_metric: metric, pricing_model: pricing_model, properties: properties)
  end

  describe ".meter_params" do
    it "maps a count metric to a counting meter keyed by Stripe customer id" do
      params = described_class.meter_params(metric)

      expect(params[:event_name]).to eq("meterly_#{organization.id}_api_calls")
      expect(params[:default_aggregation]).to eq(formula: "count")
      expect(params[:customer_mapping]).to eq(type: "by_id", event_payload_key: "stripe_customer_id")
    end

    it "maps a sum metric to a summing meter" do
      metric.update!(aggregation_type: "sum", property_name: "tokens")

      expect(described_class.meter_params(metric)[:default_aggregation]).to eq(formula: "sum")
    end

    it "refuses aggregations Stripe meters cannot express" do
      metric.update!(aggregation_type: "unique_count", property_name: "user_id")

      expect { described_class.meter_params(metric) }.to raise_error(described_class::Unsupported, /unique_count/)
    end

    it "refuses a filtered metric, because a meter cannot filter on properties" do
      metric.update!(filters: { "region" => [ "eu-west-1" ] })

      expect { described_class.meter_params(metric) }.to raise_error(described_class::Unsupported, /filter/)
    end
  end

  describe ".meter_value" do
    it "counts every event as one" do
      event = build(:usage_event, properties: {})

      expect(described_class.meter_value(metric, event)).to eq("1")
    end

    it "sends the summed property and skips one that is not a number" do
      metric.update!(aggregation_type: "sum", property_name: "tokens")

      expect(described_class.meter_value(metric, build(:usage_event, properties: { "tokens" => "1200" }))).to eq("1200")
      expect(described_class.meter_value(metric, build(:usage_event, properties: { "tokens" => "lots" }))).to be_nil
    end
  end

  describe ".price_params" do
    it "builds a monthly metered price on the meter, in the plan currency" do
      params = described_class.price_params(charge_with("per_unit", "unit_amount_cents" => "0.25"),
                                            meter_id: "mtr_1", product_id: "prod_1")

      expect(params).to include(currency: "gbp", product: "prod_1", billing_scheme: "per_unit", unit_amount_decimal: "0.25")
      expect(params[:recurring]).to eq(interval: "month", usage_type: "metered", meter: "mtr_1")
    end

    it "turns a free allowance into a free first tier" do
      params = described_class.pricing_params(charge_with("per_unit", "unit_amount_cents" => 3, "free_units" => 10))

      expect(params[:tiers_mode]).to eq("graduated")
      expect(params[:tiers]).to eq([ { up_to: 10, unit_amount_decimal: "0" }, { up_to: "inf", unit_amount_decimal: "3" } ])
    end

    it "moves graduated boundaries up by the allowance" do
      tiers = [ { "up_to" => 100, "unit_amount_cents" => 5 }, { "up_to" => nil, "unit_amount_cents" => 2 } ]
      params = described_class.pricing_params(charge_with("tiered", "tiers" => tiers, "free_units" => 50))

      expect(params[:tiers].map { |tier| tier[:up_to] }).to eq([ 50, 150, "inf" ])
      expect(params[:tiers].map { |tier| tier[:unit_amount_decimal] }).to eq(%w[0 5 2])
    end

    it "keeps volume tiers as volume tiers" do
      tiers = [ { "up_to" => 1_000, "unit_amount_cents" => 12 }, { "up_to" => nil, "unit_amount_cents" => 6 } ]
      params = described_class.pricing_params(charge_with("volume", "tiers" => tiers))

      expect(params).to include(billing_scheme: "tiered", tiers_mode: "volume")
      expect(params[:tiers].last).to include(up_to: "inf", unit_amount_decimal: "6")
    end

    it "prices packages by dividing the quantity and rounding up" do
      params = described_class.pricing_params(charge_with("package", "package_size" => 1_000, "package_amount_cents" => 500))

      expect(params).to eq(billing_scheme: "per_unit", unit_amount_decimal: "500",
                           transform_quantity: { divide_by: 1_000, round: "up" })
    end

    it "refuses shapes that would make Stripe disagree with the invoice" do
      expect { described_class.pricing_params(charge_with("package", "package_size" => 10, "package_amount_cents" => 5, "free_units" => 3)) }
        .to raise_error(described_class::Unsupported)
      expect { described_class.pricing_params(charge_with("per_unit", "unit_amount_cents" => 1, "free_units" => "2.5")) }
        .to raise_error(described_class::Unsupported, /whole number/)
    end
  end
end
