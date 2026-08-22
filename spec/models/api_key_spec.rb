require "rails_helper"

RSpec.describe ApiKey do
  let(:organization) { create(:organization) }

  it "returns the raw token once and stores only a digest" do
    key = described_class.issue!(organization: organization, name: "Ingest")

    expect(key.token).to start_with("mtr_sk_")
    expect(key.token_digest).to eq(described_class.digest(key.token))
    expect(described_class.find(key.id).token).to be_nil
  end

  it "authenticates a live token" do
    key = described_class.issue!(organization: organization, name: "Ingest")

    expect(described_class.authenticate(key.token)).to eq(key)
  end

  it "refuses a revoked token" do
    key = described_class.issue!(organization: organization, name: "Ingest")
    key.revoke!

    expect(described_class.authenticate(key.token)).to be_nil
  end

  it "refuses an unknown or blank token" do
    expect(described_class.authenticate("mtr_sk_nonsense")).to be_nil
    expect(described_class.authenticate(nil)).to be_nil
  end

  it "records use at most once a minute" do
    key = described_class.issue!(organization: organization, name: "Ingest")

    key.touch_usage!
    first = key.reload.last_used_at
    key.touch_usage!

    expect(key.reload.last_used_at).to eq(first)
  end
end
