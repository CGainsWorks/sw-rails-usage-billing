require "rails_helper"

RSpec.describe Payments::MirrorUsageJob do
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization: organization, external_id: "sub_1") }

  before { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }

  def ingest(transaction_id = "txn_1")
    Events::Ingest.call(organization: organization, attributes: {
      "transaction_id" => transaction_id, "external_subscription_id" => subscription.external_id, "code" => "calls"
    })
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "is not enqueued unless usage mirroring is switched on" do
    expect { ingest }.not_to have_enqueued_job(described_class)
  end

  it "is enqueued once per new event when mirroring to Stripe and never for a replay" do
    with_env("PAYMENT_PROVIDER" => "stripe", "STRIPE_MIRROR_USAGE" => "true") do
      expect { ingest }.to have_enqueued_job(described_class).exactly(:once)
      expect { ingest }.not_to have_enqueued_job(described_class)
    end
  end

  it "does nothing with a gateway that has no meters" do
    event = ingest.event

    expect { described_class.perform_now(event.id) }.not_to raise_error
  end
end
