require "rails_helper"

RSpec.describe "Api::V1::Invoices" do
  let(:organization) { create(:organization, slug: "acme") }
  let(:api_key) { ApiKey.issue!(organization: organization, name: "Ingest") }
  let(:headers) { api_headers(api_key.token) }
  let(:subscription) { create(:subscription, organization: organization, started_at: Time.zone.parse("2026-01-01 00:00:00 UTC")) }
  let(:invoice) do
    Invoice.create!(organization: organization, customer: subscription.customer, subscription: subscription,
                    currency: "GBP", period_start: Time.zone.parse("2026-01-01 00:00:00 UTC"),
                    period_end: Time.zone.parse("2026-02-01 00:00:00 UTC"),
                    subtotal_cents: 1_000, tax_cents: 200, total_cents: 1_200)
  end

  it "lists invoices" do
    invoice

    get "/api/v1/invoices", headers: headers

    expect(json["invoices"].length).to eq(1)
    expect(json["invoices"].first["total_cents"]).to eq(1_200)
  end

  it "filters by status" do
    invoice
    Billing::FinalizeInvoice.call(invoice: invoice)

    get "/api/v1/invoices", params: { status: "draft" }, headers: headers

    expect(json["invoices"]).to be_empty
  end

  it "filters by customer" do
    invoice

    get "/api/v1/invoices", params: { external_customer_id: subscription.customer.external_id }, headers: headers

    expect(json["invoices"].length).to eq(1)
  end

  it "fetches one invoice by number, with its lines" do
    invoice.line_items.create!(kind: "usage", description: "API requests", quantity: 10, amount_cents: 1_000)
    Billing::FinalizeInvoice.call(invoice: invoice)

    get "/api/v1/invoices/#{invoice.reload.number}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(json.dig("invoice", "line_items").first["description"]).to eq("API requests")
  end

  it "fetches one invoice by id" do
    get "/api/v1/invoices/#{invoice.id}", headers: headers

    expect(json.dig("invoice", "id")).to eq(invoice.id)
  end

  it "cannot read another organization's invoice" do
    other_subscription = create(:subscription)
    other = Invoice.create!(organization: other_subscription.organization, customer: other_subscription.customer,
                            subscription: other_subscription, currency: "GBP",
                            period_start: 1.month.ago, period_end: Time.current)

    get "/api/v1/invoices/#{other.id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it "lists the plans in the catalogue" do
    plan = create(:plan, organization: organization, code: "growth")
    create(:charge, plan: plan, billable_metric: create(:billable_metric, organization: organization, code: "calls"),
                    pricing_model: "per_unit", properties: { "unit_amount_cents" => 5 })

    get "/api/v1/plans", headers: headers

    expect(json["plans"].first["charges"].first).to include("metric_code" => "calls", "pricing_model" => "per_unit")
  end
end
