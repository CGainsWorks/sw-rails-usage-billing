require "rails_helper"

RSpec.describe Payments::Collect do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization, external_id: external_id) }
  let(:external_id) { "cus_ok" }
  let(:subscription) { create(:subscription, organization: organization, customer: customer) }
  let(:invoice) do
    Invoice.create!(organization: organization, customer: customer, subscription: subscription,
                    status: "finalized", currency: "GBP", period_start: 1.month.ago, period_end: Time.current,
                    subtotal_cents: 1_000, tax_cents: 0, total_cents: 1_000, finalized_at: Time.current)
  end

  it "marks the invoice paid and records the attempt" do
    attempt = described_class.call(invoice: invoice)

    expect(attempt).to be_succeeded
    expect(attempt.amount_cents).to eq(1_000)
    expect(invoice.reload).to be_paid
  end

  context "when the simulated gateway declines" do
    let(:external_id) { "decline_riverbank" }

    it "leaves the invoice unpaid and records why" do
      attempt = described_class.call(invoice: invoice)

      expect(attempt).to be_failed
      expect(attempt.failure_reason).to eq("card_declined")
      expect(invoice.reload).to be_finalized
    end

    it "announces the failure" do
      create(:webhook_endpoint, organization: organization)

      described_class.call(invoice: invoice)

      expect(WebhookDelivery.last.event_type).to eq("invoice.payment_failed")
    end
  end

  it "refuses to charge a draft invoice" do
    invoice.update!(status: "draft")

    expect(described_class.call(invoice: invoice)).to be_nil
    expect(invoice.payment_attempts.count).to eq(0)
  end

  it "raises for an unknown provider" do
    ENV["PAYMENT_PROVIDER"] = "carrier_pigeon"

    expect { Payments::Gateway.current }.to raise_error(ArgumentError)
  ensure
    ENV.delete("PAYMENT_PROVIDER")
  end
end
