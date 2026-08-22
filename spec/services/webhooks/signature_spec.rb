require "rails_helper"

RSpec.describe Webhooks::Signature do
  let(:payload) { { id: "evt_1" }.to_json }
  let(:secret) { "whsec_test" }

  it "signs and verifies a payload" do
    header = described_class.header(payload: payload, secret: secret)

    expect(described_class.verify(header_value: header, payload: payload, secret: secret)).to be(true)
  end

  it "rejects a payload that was altered in flight" do
    header = described_class.header(payload: payload, secret: secret)

    expect(described_class.verify(header_value: header, payload: "{}", secret: secret)).to be(false)
  end

  it "rejects the wrong secret" do
    header = described_class.header(payload: payload, secret: secret)

    expect(described_class.verify(header_value: header, payload: payload, secret: "whsec_other")).to be(false)
  end

  it "rejects a replay from outside the tolerance" do
    header = described_class.header(payload: payload, secret: secret, timestamp: 10.minutes.ago)

    expect(described_class.verify(header_value: header, payload: payload, secret: secret)).to be(false)
  end

  it "rejects a header it cannot read" do
    expect(described_class.verify(header_value: "nonsense", payload: payload, secret: secret)).to be(false)
    expect(described_class.verify(header_value: nil, payload: payload, secret: secret)).to be(false)
  end
end
