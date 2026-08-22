require "rails_helper"

RSpec.describe Webhooks::Deliver do
  let(:endpoint) { create(:webhook_endpoint) }
  let(:delivery) do
    endpoint.webhook_deliveries.create!(event_type: "invoice.finalized", payload: { "type" => "invoice.finalized" },
                                        deliver_after: Time.current)
  end

  def stub_response(code)
    response = instance_double(Net::HTTPResponse, code: code.to_s)
    allow_any_instance_of(described_class).to receive(:post).and_return(response)
  end

  it "marks a 2xx as delivered" do
    stub_response(200)

    described_class.call(delivery: delivery)

    expect(delivery.reload.status).to eq("delivered")
    expect(delivery.attempts).to eq(1)
    expect(delivery.delivered_at).to be_present
  end

  it "reschedules a 500 with a backoff instead of raising" do
    stub_response(500)

    described_class.call(delivery: delivery)

    expect(delivery.reload.status).to eq("pending")
    expect(delivery.last_error).to match(/500/)
    expect(delivery.deliver_after).to be > Time.current
  end

  it "reschedules a connection failure" do
    allow_any_instance_of(described_class).to receive(:post).and_raise(Errno::ECONNREFUSED)

    described_class.call(delivery: delivery)

    expect(delivery.reload.status).to eq("pending")
    expect(delivery.last_error).to match(/Errno::ECONNREFUSED/)
  end

  it "gives up once the attempts are exhausted" do
    delivery.update!(attempts: WebhookDelivery::MAX_ATTEMPTS - 1)
    stub_response(503)

    described_class.call(delivery: delivery)

    expect(delivery.reload.status).to eq("failed")
  end

  it "does not deliver the same event twice" do
    delivery.update!(status: "delivered", delivered_at: Time.current)
    stub_response(200)

    expect { described_class.call(delivery: delivery) }.not_to change { delivery.reload.attempts }
  end

  it "backs off exponentially" do
    expect(WebhookDelivery.new(attempts: 1).next_backoff).to eq(30.seconds)
    expect(WebhookDelivery.new(attempts: 3).next_backoff).to eq(120.seconds)
  end
end
