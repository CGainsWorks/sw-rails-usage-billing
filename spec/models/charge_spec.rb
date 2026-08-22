require "rails_helper"

RSpec.describe Charge do
  let(:plan) { create(:plan) }
  let(:metric) { create(:billable_metric, organization: plan.organization) }

  it "refuses a price the pricing model cannot use" do
    charge = described_class.new(plan: plan, billable_metric: metric, pricing_model: "package",
                                 properties: { "package_amount_cents" => 100 })

    expect(charge).not_to be_valid
    expect(charge.errors[:properties].first).to match(/package_size/)
  end

  it "refuses an unknown pricing model" do
    charge = described_class.new(plan: plan, billable_metric: metric, pricing_model: "vibes", properties: {})

    expect(charge).not_to be_valid
  end

  it "accepts a well formed tiered price" do
    charge = described_class.new(plan: plan, billable_metric: metric, pricing_model: "tiered",
                                 properties: { "tiers" => [ { "up_to" => nil, "unit_amount_cents" => "0.5" } ] })

    expect(charge).to be_valid
  end

  it "bills a plan for the same metric only once" do
    described_class.create!(plan: plan, billable_metric: metric, pricing_model: "per_unit",
                            properties: { "unit_amount_cents" => 1 })
    duplicate = described_class.new(plan: plan, billable_metric: metric, pricing_model: "per_unit",
                                    properties: { "unit_amount_cents" => 1 })

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
