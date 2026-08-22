require "rails_helper"

RSpec.describe "Api::V1::Subscriptions" do
  let(:organization) { create(:organization) }
  let(:api_key) { ApiKey.issue!(organization: organization, name: "Ingest") }
  let(:headers) { api_headers(api_key.token) }
  let(:metric) { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }
  let(:plan) do
    create(:plan, organization: organization, code: "growth", base_amount_cents: 10_000).tap do |plan|
      create(:charge, plan: plan, billable_metric: metric, pricing_model: "per_unit",
                      properties: { "unit_amount_cents" => 20 })
    end
  end
  let(:customer) { create(:customer, organization: organization, external_id: "cus_1", tax_rate_bps: 2_000) }

  describe "POST /api/v1/customers" do
    it "creates a customer" do
      post "/api/v1/customers", params: { customer: { external_id: "cus_new", name: "New Ltd" } }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(organization.customers.find_by(external_id: "cus_new").name).to eq("New Ltd")
    end

    it "updates instead of failing when the customer already exists" do
      customer

      post "/api/v1/customers", params: { customer: { external_id: "cus_1", name: "Renamed" } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(customer.reload.name).to eq("Renamed")
      expect(organization.customers.count).to eq(1)
    end

    it "reports validation failures" do
      post "/api/v1/customers", params: { customer: { external_id: "cus_bad", name: "" } }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include(/Name/)
    end
  end

  describe "POST /api/v1/subscriptions" do
    it "subscribes a customer to a plan" do
      params = { subscription: { external_id: "sub_new", external_customer_id: customer.external_id,
                                 plan_code: plan.code, started_at: "2026-01-01T00:00:00Z" } }

      post "/api/v1/subscriptions", params: params.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(json.dig("subscription", "current_period_start")).to be_present
    end

    it "rejects an unknown plan" do
      params = { subscription: { external_id: "sub_new", external_customer_id: customer.external_id, plan_code: "nope" } }

      post "/api/v1/subscriptions", params: params.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/subscriptions/:id/current_usage" do
    let(:subscription) do
      create(:subscription, organization: organization, customer: customer, plan: plan,
                            external_id: "sub_1", started_at: 10.days.ago)
    end

    it "quotes the period that is still running" do
      3.times do |index|
        create(:usage_event, organization: organization, subscription: subscription, code: "calls",
                             occurred_at: 2.days.ago + index.minutes)
      end

      get "/api/v1/subscriptions/#{subscription.external_id}/current_usage", headers: headers

      expect(response).to have_http_status(:ok)
      usage = json["current_usage"]
      expect(usage["subtotal_cents"]).to eq(10_060)
      expect(usage["tax_cents"]).to eq(2_012)
      expect(usage["lines"].map { |line| line["kind"] }).to eq(%w[subscription_fee usage])
    end

    it "404s for a subscription that belongs to somebody else" do
      other = create(:organization)
      create(:subscription, organization: other, external_id: "sub_other")

      get "/api/v1/subscriptions/sub_other/current_usage", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/subscriptions/:id/terminate" do
    let(:subscription) do
      create(:subscription, organization: organization, customer: customer, plan: plan,
                            external_id: "sub_1", started_at: 10.days.ago)
    end

    it "terminates the subscription" do
      post "/api/v1/subscriptions/#{subscription.external_id}/terminate", headers: headers

      expect(json.dig("subscription", "status")).to eq("terminated")
      expect(subscription.reload.terminated_at).to be_present
    end

    it "is safe to call twice" do
      post "/api/v1/subscriptions/#{subscription.external_id}/terminate", headers: headers
      terminated_at = subscription.reload.terminated_at
      post "/api/v1/subscriptions/#{subscription.external_id}/terminate", headers: headers

      expect(subscription.reload.terminated_at).to eq(terminated_at)
    end
  end
end
