require "rails_helper"

RSpec.describe Billing::PeriodStatement do
  let(:organization) { create(:organization) }
  let(:metric) { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }
  let(:plan) do
    create(:plan, organization: organization, base_amount_cents: 10_000).tap do |plan|
      create(:charge, plan: plan, billable_metric: metric, pricing_model: "per_unit",
                      properties: { "unit_amount_cents" => 25 })
    end
  end
  let(:customer) { create(:customer, organization: organization, tax_rate_bps: 2_000) }
  let(:subscription) do
    create(:subscription, organization: organization, customer: customer, plan: plan,
                          started_at: Time.zone.parse("2026-01-01 00:00:00 UTC"))
  end

  def record_calls(count)
    count.times do |index|
      create(:usage_event, organization: organization, subscription: subscription, code: "calls",
                           occurred_at: Time.zone.parse("2026-01-10 09:00:00 UTC") + index.minutes)
    end
  end

  def statement(period = subscription.billing_period_at(Time.zone.parse("2026-01-15 00:00:00 UTC")))
    described_class.call(subscription: subscription, period: period)
  end

  it "bills the recurring fee even with no usage" do
    result = statement

    expect(result.lines.map(&:kind)).to eq([ "subscription_fee" ])
    expect(result.subtotal_cents).to eq(10_000)
  end

  it "adds a line per charge that saw usage" do
    record_calls(4)
    result = statement

    usage = result.usage_lines.first
    expect(usage.quantity).to eq(4)
    expect(usage.amount_cents).to eq(100)
    expect(result.subtotal_cents).to eq(10_100)
  end

  it "applies the customer tax rate to the subtotal" do
    record_calls(4)
    result = statement

    expect(result.tax_cents).to eq(2_020)
    expect(result.total_cents).to eq(12_120)
  end

  it "leaves tax off when the customer has no rate" do
    customer.update!(tax_rate_bps: 0)

    expect(statement.tax_cents).to eq(0)
  end

  describe "minimum commitment" do
    before { plan.update!(minimum_amount_cents: 25_000) }

    it "trues up to the commitment when usage falls short" do
      record_calls(4)
      result = statement

      true_up = result.lines.find { |line| line.kind == "minimum_true_up" }
      expect(true_up.amount_cents).to eq(25_000 - 10_100)
      expect(result.subtotal_cents).to eq(25_000)
    end

    it "adds nothing once usage passes the commitment" do
      record_calls(700)

      expect(statement.lines.map(&:kind)).not_to include("minimum_true_up")
    end
  end

  describe "a period cut short by a termination" do
    let(:period) do
      subscription.update!(status: "terminated", terminated_at: Time.zone.parse("2026-01-16 00:00:00 UTC"))
      subscription.closed_billing_periods(up_to: Time.zone.parse("2026-02-05 00:00:00 UTC")).first
    end

    it "prorates the recurring fee by the days that were served" do
      result = statement(period)
      fee = result.lines.find { |line| line.kind == "subscription_fee" }

      # 15 of 31 days of a 10_000c fee.
      expect(fee.amount_cents).to eq(4_839)
      expect(fee.breakdown["prorated"]).to be(true)
    end

    it "prorates the minimum commitment as well" do
      plan.update!(minimum_amount_cents: 20_000)
      result = statement(period)

      expect(result.subtotal_cents).to eq((BigDecimal("20000") * 15 / 31).round)
    end

    it "counts only the usage inside the shortened window" do
      record_calls(2)
      create(:usage_event, organization: organization, subscription: subscription, code: "calls",
                           occurred_at: Time.zone.parse("2026-01-20 09:00:00 UTC"))

      expect(statement(period).usage_lines.first.quantity).to eq(2)
    end
  end
end
