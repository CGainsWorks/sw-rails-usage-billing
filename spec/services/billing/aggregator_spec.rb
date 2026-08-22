require "rails_helper"

RSpec.describe Billing::Aggregator do
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization: organization, started_at: Time.zone.parse("2026-01-01 00:00:00 UTC")) }
  let(:period) { subscription.billing_period_at(Time.zone.parse("2026-01-15 00:00:00 UTC")) }

  def record(code, occurred_at, properties = {})
    create(:usage_event, organization: organization, subscription: subscription,
                         code: code, occurred_at: Time.zone.parse(occurred_at), properties: properties)
  end

  def aggregate(metric) = described_class.call(subscription: subscription, metric: metric, period: period)

  it "counts events" do
    metric = create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count")
    3.times { |index| record("calls", "2026-01-#{10 + index} 09:00:00 UTC") }

    expect(aggregate(metric)).to eq(3)
  end

  it "ignores events outside the period" do
    metric = create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count")
    record("calls", "2025-12-31 23:59:59 UTC")
    record("calls", "2026-02-01 00:00:00 UTC")
    record("calls", "2026-01-31 23:59:59 UTC")

    expect(aggregate(metric)).to eq(1)
  end

  it "ignores events for other metrics" do
    metric = create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count")
    record("calls", "2026-01-05 09:00:00 UTC")
    record("emails", "2026-01-05 09:00:00 UTC")

    expect(aggregate(metric)).to eq(1)
  end

  it "sums a numeric property" do
    metric = create(:billable_metric, organization: organization, code: "data", aggregation_type: "sum", property_name: "gigabytes")
    record("data", "2026-01-05 09:00:00 UTC", { "gigabytes" => "1.5" })
    record("data", "2026-01-06 09:00:00 UTC", { "gigabytes" => "2.25" })

    expect(aggregate(metric)).to eq(BigDecimal("3.75"))
  end

  it "skips events whose property is not a number rather than failing the run" do
    metric = create(:billable_metric, organization: organization, code: "data", aggregation_type: "sum", property_name: "gigabytes")
    record("data", "2026-01-05 09:00:00 UTC", { "gigabytes" => "1.5" })
    record("data", "2026-01-06 09:00:00 UTC", { "gigabytes" => "lots" })

    expect(aggregate(metric)).to eq(BigDecimal("1.5"))
  end

  it "returns zero when there is nothing to sum" do
    metric = create(:billable_metric, organization: organization, code: "data", aggregation_type: "sum", property_name: "gigabytes")

    expect(aggregate(metric)).to eq(0)
  end

  it "takes the peak value" do
    metric = create(:billable_metric, organization: organization, code: "seats", aggregation_type: "max", property_name: "seats")
    record("seats", "2026-01-05 09:00:00 UTC", { "seats" => "4" })
    record("seats", "2026-01-06 09:00:00 UTC", { "seats" => "11" })
    record("seats", "2026-01-07 09:00:00 UTC", { "seats" => "7" })

    expect(aggregate(metric)).to eq(11)
  end

  it "counts distinct values" do
    metric = create(:billable_metric, organization: organization, code: "projects", aggregation_type: "unique_count", property_name: "project_id")
    record("projects", "2026-01-05 09:00:00 UTC", { "project_id" => "a" })
    record("projects", "2026-01-06 09:00:00 UTC", { "project_id" => "a" })
    record("projects", "2026-01-07 09:00:00 UTC", { "project_id" => "b" })

    expect(aggregate(metric)).to eq(2)
  end

  it "applies a property filter" do
    metric = create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count",
                                      filters: { "region" => [ "eu-west-1" ] })
    record("calls", "2026-01-05 09:00:00 UTC", { "region" => "eu-west-1" })
    record("calls", "2026-01-06 09:00:00 UTC", { "region" => "us-east-1" })

    expect(aggregate(metric)).to eq(1)
  end

  it "ignores events belonging to another subscription" do
    metric = create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count")
    other = create(:subscription, organization: organization, started_at: subscription.started_at)
    create(:usage_event, organization: organization, subscription: other, code: "calls",
                         occurred_at: Time.zone.parse("2026-01-05 09:00:00 UTC"))
    record("calls", "2026-01-05 09:00:00 UTC")

    expect(aggregate(metric)).to eq(1)
  end
end
