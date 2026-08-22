require "rails_helper"

RSpec.describe "Dashboard" do
  let(:organization) { create(:organization) }
  let!(:user) { create(:user, organization: organization) }

  it "sends a signed out visitor to the sign in page" do
    get root_path

    expect(response).to redirect_to(new_session_path)
  end

  it "refuses the wrong password" do
    post session_path, params: { email_address: user.email_address, password: "nope" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns to the page that was asked for after signing in" do
    get customers_path
    sign_in(user)

    expect(response).to redirect_to(customers_path)
  end

  context "when signed in" do
    let(:metric) { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }
    let(:plan) do
      create(:plan, organization: organization, base_amount_cents: 5_000).tap do |plan|
        create(:charge, plan: plan, billable_metric: metric, pricing_model: "tiered",
                        properties: { "tiers" => [ { "up_to" => 100, "unit_amount_cents" => 5 },
                                                   { "up_to" => nil, "unit_amount_cents" => 2 } ] })
      end
    end
    let(:customer) { create(:customer, organization: organization, tax_rate_bps: 2_000) }
    let(:subscription) do
      create(:subscription, organization: organization, customer: customer, plan: plan,
                            started_at: Time.zone.parse("2026-01-01 00:00:00 UTC"))
    end

    before do
      sign_in(user)
      120.times do |index|
        create(:usage_event, organization: organization, subscription: subscription, code: "calls",
                             occurred_at: Time.zone.parse("2026-01-05 09:00:00 UTC") + index.minutes)
      end
    end

    it "shows the overview" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(organization.name)
    end

    it "lists customers and opens one" do
      get customers_path
      expect(response.body).to include(customer.name)

      get customer_path(customer)
      expect(response).to have_http_status(:ok)
    end

    it "shows a plan with its tier table" do
      get plan_path(plan)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("100 and above")
    end

    it "shows the running total for the open period" do
      travel_to(Time.zone.parse("2026-01-20 00:00:00 UTC")) do
        get subscription_path(subscription)
      end

      # 100 units at 5c plus 20 at 2c, on top of the 5,000c fee.
      expect(response.body).to include("£55.40")
    end

    it "shows an invoice with its tier breakdown" do
      invoice = travel_to(Time.zone.parse("2026-02-05 00:00:00 UTC")) do
        Billing::GenerateInvoiceJob.perform_now(subscription.id, "2026-01-01T00:00:00Z")
      end

      get invoice_path(invoice)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(invoice.number)
      expect(response.body).to include("0 to 100")
    end

    it "lists events and filters them by metric" do
      get usage_events_path(code: "calls")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("calls")
    end

    it "issues an API key and shows it exactly once" do
      post api_keys_path, params: { name: "Ingest" }
      follow_redirect!

      expect(response.body).to include("mtr_sk_")

      get settings_path
      expect(response.body).not_to include("mtr_sk_1")
    end

    it "revokes an API key" do
      key = ApiKey.issue!(organization: organization, name: "Ingest")

      delete api_key_path(key)

      expect(key.reload).to be_revoked
    end

    it "adds and removes a webhook endpoint" do
      post webhook_endpoints_path, params: { url: "https://receiver.test/hooks" }
      endpoint = organization.webhook_endpoints.last
      expect(endpoint.secret).to start_with("whsec_")

      delete webhook_endpoint_path(endpoint)
      expect(organization.webhook_endpoints.count).to eq(0)
    end

    it "signs out" do
      delete session_path

      expect(response).to redirect_to(new_session_path)
      get root_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
