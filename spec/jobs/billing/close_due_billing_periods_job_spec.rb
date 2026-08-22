require "rails_helper"

RSpec.describe Billing::CloseDueBillingPeriodsJob do
  let(:organization) { create(:organization) }
  let(:subscription) do
    create(:subscription, organization: organization, started_at: Time.zone.parse("2026-01-01 00:00:00 UTC"))
  end

  it "queues one invoice job per closed period" do
    subscription

    expect { described_class.perform_now(up_to: Time.zone.parse("2026-03-05 00:00:00 UTC")) }
      .to have_enqueued_job(Billing::GenerateInvoiceJob).twice
  end

  it "queues nothing while the first period is still running" do
    subscription

    expect { described_class.perform_now(up_to: Time.zone.parse("2026-01-20 00:00:00 UTC")) }
      .not_to have_enqueued_job(Billing::GenerateInvoiceJob)
  end

  it "skips a period that has already been invoiced" do
    Invoice.create!(organization: organization, customer: subscription.customer, subscription: subscription,
                    currency: "GBP", period_start: Time.zone.parse("2026-01-01 00:00:00 UTC"),
                    period_end: Time.zone.parse("2026-02-01 00:00:00 UTC"))

    expect { described_class.perform_now(up_to: Time.zone.parse("2026-02-05 00:00:00 UTC")) }
      .not_to have_enqueued_job(Billing::GenerateInvoiceJob)
  end

  it "still bills a terminated subscription for the part period it used" do
    subscription.update!(status: "terminated", terminated_at: Time.zone.parse("2026-01-20 00:00:00 UTC"))

    expect(described_class.perform_now(up_to: Time.zone.parse("2026-02-05 00:00:00 UTC"))).to eq(1)
  end
end

RSpec.describe Billing::GenerateInvoiceJob do
  let(:organization) { create(:organization) }
  let(:subscription) do
    create(:subscription, organization: organization, started_at: Time.zone.parse("2026-01-01 00:00:00 UTC"))
  end

  around { |example| travel_to(Time.zone.parse("2026-02-05 00:00:00 UTC")) { example.run } }

  it "generates and finalizes the invoice for the period" do
    invoice = described_class.perform_now(subscription.id, "2026-01-01T00:00:00Z")

    expect(invoice).to be_finalized
    expect(invoice.number).to be_present
  end

  it "is safe to run twice" do
    described_class.perform_now(subscription.id, "2026-01-01T00:00:00Z")
    described_class.perform_now(subscription.id, "2026-01-01T00:00:00Z")

    expect(Invoice.count).to eq(1)
  end

  it "does nothing for a period that is not closed" do
    expect(described_class.perform_now(subscription.id, "2026-02-01T00:00:00Z")).to be_nil
    expect(Invoice.count).to eq(0)
  end
end
