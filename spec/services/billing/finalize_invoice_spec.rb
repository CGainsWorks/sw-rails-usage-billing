require "rails_helper"

RSpec.describe Billing::FinalizeInvoice do
  let(:organization) { create(:organization, slug: "acme") }
  let(:subscription) { create(:subscription, organization: organization, started_at: Time.zone.parse("2026-01-01 00:00:00 UTC")) }

  def build_invoice(period_start: "2026-01-01 00:00:00 UTC", period_end: "2026-02-01 00:00:00 UTC")
    create_invoice = Invoice.create!(
      organization: organization, customer: subscription.customer, subscription: subscription,
      currency: "GBP", period_start: Time.zone.parse(period_start), period_end: Time.zone.parse(period_end),
      subtotal_cents: 1_000, tax_cents: 200, total_cents: 1_200
    )
    create_invoice
  end

  it "numbers the invoice per organization and year" do
    first = described_class.call(invoice: build_invoice)
    second = described_class.call(invoice: build_invoice(period_start: "2026-02-01 00:00:00 UTC", period_end: "2026-03-01 00:00:00 UTC"))

    expect(first.number).to eq("INV-ACME-2026-00001")
    expect(second.number).to eq("INV-ACME-2026-00002")
  end

  it "restarts the sequence in a new year" do
    described_class.call(invoice: build_invoice)
    next_year = described_class.call(invoice: build_invoice(period_start: "2026-12-01 00:00:00 UTC", period_end: "2027-01-01 00:00:00 UTC"))

    expect(next_year.number).to eq("INV-ACME-2027-00001")
  end

  it "moves the invoice out of draft" do
    invoice = described_class.call(invoice: build_invoice)

    expect(invoice).to be_finalized
    expect(invoice.finalized_at).to be_present
  end

  it "queues collection" do
    expect { described_class.call(invoice: build_invoice) }
      .to have_enqueued_job(Payments::ChargeInvoiceJob)
  end

  it "announces the invoice to every active webhook endpoint" do
    create(:webhook_endpoint, organization: organization)
    create(:webhook_endpoint, organization: organization, url: "https://second.test/hooks")
    create(:webhook_endpoint, organization: organization, url: "https://off.test/hooks", active: false)

    expect { described_class.call(invoice: build_invoice) }.to change(WebhookDelivery, :count).by(2)
    expect(WebhookDelivery.pluck(:event_type).uniq).to eq([ "invoice.finalized" ])
  end

  it "does nothing to an invoice that is already finalized" do
    invoice = described_class.call(invoice: build_invoice)

    expect { described_class.call(invoice: invoice) }.not_to change { invoice.reload.number }
  end
end
