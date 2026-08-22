require "rails_helper"

RSpec.describe Subscription do
  it "refuses a plan from another organization" do
    subscription = build(:subscription, organization: create(:organization), plan: create(:plan))

    expect(subscription).not_to be_valid
    expect(subscription.errors[:plan]).to include(/same organization/)
  end

  it "refuses a customer from another organization" do
    subscription = build(:subscription, organization: create(:organization), customer: create(:customer))

    expect(subscription).not_to be_valid
    expect(subscription.errors[:customer]).to include(/same organization/)
  end

  it "requires a unique external id inside the organization" do
    existing = create(:subscription, external_id: "sub_1")
    duplicate = build(:subscription, organization: existing.organization, external_id: "sub_1")

    expect(duplicate).not_to be_valid
  end

  it "lets a different organization reuse an external id" do
    create(:subscription, external_id: "sub_1")

    expect(build(:subscription, external_id: "sub_1")).to be_valid
  end

  it "records when it was terminated" do
    subscription = create(:subscription)
    subscription.terminate!

    expect(subscription).to be_terminated
    expect(subscription.terminated_at).to be_present
  end
end
