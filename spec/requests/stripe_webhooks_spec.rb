require "rails_helper"

RSpec.describe "Stripe webhooks" do
  # Generated for this run only. Nothing resembling a signing secret is
  # committed and the examples do not need a Stripe account.
  let(:secret) { "whsec_#{SecureRandom.hex(24)}" }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, organization: organization, customer: customer) }
  let(:invoice) do
    Invoice.create!(organization: organization, customer: customer, subscription: subscription,
                    status: "finalized", number: "INV-HOOK-2026-00001", currency: "GBP",
                    period_start: 1.month.ago, period_end: Time.current, finalized_at: Time.current,
                    subtotal_cents: 1_000, tax_cents: 0, total_cents: 1_000)
  end
  let(:stripe_invoice_id) { "in_#{SecureRandom.alphanumeric(14)}" }

  around do |example|
    ENV["STRIPE_WEBHOOK_SECRET"] = secret
    example.run
  ensure
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  before do
    ProviderReference.create!(provider: "stripe", record: invoice, kind: "invoice", external_id: stripe_invoice_id)
  end

  def event_body(type, id: "evt_#{SecureRandom.alphanumeric(14)}")
    { id: id, object: "event", type: type, api_version: Stripe::ApiVersion::CURRENT,
      data: { object: { id: stripe_invoice_id, object: "invoice", metadata: { meterly_invoice_id: invoice.id.to_s } } } }.to_json
  end

  def signature_for(body, signing_secret: secret, at: Time.now)
    Stripe::Webhook::Signature.generate_header(at, Stripe::Webhook::Signature.compute_signature(at, body, signing_secret))
  end

  def deliver(body, signature)
    post "/webhooks/stripe", params: body, headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => signature }
  end

  it "marks the invoice paid on a correctly signed invoice.paid" do
    body = event_body("invoice.paid")

    deliver(body, signature_for(body))

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["outcome"]).to eq("marked_paid")
    expect(invoice.reload).to be_paid
    expect(invoice.payment_attempts.sole).to have_attributes(provider: "stripe", provider_reference: stripe_invoice_id)
  end

  it "treats a redelivered invoice.paid as already handled" do
    body = event_body("invoice.paid")
    2.times { deliver(body, signature_for(body)) }

    expect(JSON.parse(response.body)["outcome"]).to eq("already_paid")
    expect(invoice.payment_attempts.count).to eq(1)
  end

  it "records a payment failure once per Stripe event and announces it" do
    create(:webhook_endpoint, organization: organization)
    body = event_body("invoice.payment_failed", id: "evt_failed_once")

    2.times { deliver(body, signature_for(body)) }

    expect(invoice.reload).to be_finalized
    expect(invoice.payment_attempts.where(status: "failed").count).to eq(1)
    expect(WebhookDelivery.where(event_type: "invoice.payment_failed").count).to eq(1)
  end

  it "rejects a body signed with a different secret" do
    body = event_body("invoice.paid")

    deliver(body, signature_for(body, signing_secret: "whsec_#{SecureRandom.hex(24)}"))

    expect(response).to have_http_status(:bad_request)
    expect(invoice.reload).to be_finalized
  end

  it "rejects a body altered after signing" do
    body = event_body("invoice.paid")
    signature = signature_for(body)

    deliver(body.sub("invoice.paid", "invoice.payment_failed"), signature)

    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a replay from outside the five minute tolerance" do
    body = event_body("invoice.paid")

    deliver(body, signature_for(body, at: 10.minutes.ago.to_time))

    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a request with no signature at all" do
    deliver(event_body("invoice.paid"), "")

    expect(response).to have_http_status(:bad_request)
  end

  it "acknowledges event types it does not act on" do
    body = { id: "evt_other", object: "event", type: "customer.created", data: { object: { id: "cus_1", object: "customer" } } }.to_json

    deliver(body, signature_for(body))

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["outcome"]).to eq("ignored")
  end

  it "refuses to run without a signing secret configured" do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
    body = event_body("invoice.paid")

    deliver(body, signature_for(body))

    expect(response).to have_http_status(:service_unavailable)
  end
end
