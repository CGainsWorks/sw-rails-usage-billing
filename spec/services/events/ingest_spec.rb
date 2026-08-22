require "rails_helper"

RSpec.describe Events::Ingest do
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization: organization, external_id: "sub_1", started_at: 2.months.ago) }
  before { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }

  def ingest(overrides = {})
    described_class.call(organization: organization, attributes: {
      "transaction_id" => "txn_1", "external_subscription_id" => subscription.external_id,
      "code" => "calls", "timestamp" => 1.hour.ago.iso8601, "properties" => { "region" => "eu-west-1" }
    }.merge(overrides))
  end

  it "stores the event" do
    result = ingest

    expect(result).to be_success
    expect(result.status).to eq("accepted")
    expect(result.event.properties).to eq({ "region" => "eu-west-1" })
    expect(result.event.subscription).to eq(subscription)
  end

  it "treats a replayed transaction id as a duplicate rather than a new charge" do
    ingest
    result = ingest("properties" => { "region" => "us-east-1" })

    expect(result.status).to eq("duplicate")
    expect(UsageEvent.count).to eq(1)
    expect(UsageEvent.first.properties).to eq({ "region" => "eu-west-1" })
  end

  it "lets two organizations use the same transaction id" do
    other = create(:organization)
    other_subscription = create(:subscription, organization: other, external_id: "sub_1", started_at: 2.months.ago)
    create(:billable_metric, organization: other, code: "calls", aggregation_type: "count")

    ingest
    result = described_class.call(organization: other, attributes: {
      "transaction_id" => "txn_1", "external_subscription_id" => other_subscription.external_id,
      "code" => "calls", "timestamp" => 1.hour.ago.iso8601
    })

    expect(result.status).to eq("accepted")
  end

  it "rejects an unknown subscription" do
    result = ingest("external_subscription_id" => "sub_nope")

    expect(result.status).to eq("rejected")
    expect(result.errors.first).to match(/was not found/)
  end

  it "rejects a metric code that is not billable" do
    result = ingest("code" => "teleports")

    expect(result.errors.first).to match(/no billable metric/)
  end

  it "requires a transaction id" do
    expect(ingest("transaction_id" => "").errors.first).to match(/transaction_id/)
  end

  it "rejects a timestamp from the future" do
    expect(ingest("timestamp" => 1.hour.from_now.iso8601).errors.first).to match(/future/)
  end

  it "rejects a timestamp from before the subscription started" do
    expect(ingest("timestamp" => 6.months.ago.iso8601).errors.first).to match(/before the subscription/)
  end

  it "rejects a timestamp after the subscription was terminated" do
    subscription.update!(status: "terminated", terminated_at: 1.day.ago)

    expect(ingest("timestamp" => 1.hour.ago.iso8601).errors.first).to match(/terminated/)
  end

  it "rejects a timestamp it cannot parse" do
    expect(ingest("timestamp" => "yesterday-ish").errors.first).to match(/valid time/)
  end

  it "accepts epoch seconds" do
    result = ingest("timestamp" => 1.hour.ago.to_i)

    expect(result).to be_success
    expect(result.event.occurred_at).to be_within(1.second).of(1.hour.ago)
  end

  it "defaults a missing timestamp to now" do
    result = ingest("timestamp" => nil)

    expect(result.event.occurred_at).to be_within(5.seconds).of(Time.current)
  end
end

RSpec.describe Events::IngestBatch do
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization: organization, external_id: "sub_1", started_at: 2.months.ago) }
  before { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }

  it "reports on each event separately so one bad row cannot reject the batch" do
    events = [
      { "transaction_id" => "a", "external_subscription_id" => subscription.external_id, "code" => "calls" },
      { "transaction_id" => "b", "external_subscription_id" => "missing", "code" => "calls" },
      { "transaction_id" => "a", "external_subscription_id" => subscription.external_id, "code" => "calls" }
    ]

    summary = described_class.call(organization: organization, events: events)

    expect(summary.accepted).to eq(1)
    expect(summary.rejected).to eq(1)
    expect(summary.duplicates).to eq(1)
    expect(UsageEvent.count).to eq(1)
  end
end
