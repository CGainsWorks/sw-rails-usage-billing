require "rails_helper"

RSpec.describe "Api::V1::Events" do
  let(:organization) { create(:organization) }
  let(:api_key) { ApiKey.issue!(organization: organization, name: "Ingest") }
  let(:subscription) { create(:subscription, organization: organization, external_id: "sub_1", started_at: 2.months.ago) }
  let(:headers) { api_headers(api_key.token) }

  before { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }

  def event_payload(overrides = {})
    { event: { transaction_id: "txn_1", external_subscription_id: subscription.external_id,
               code: "calls", timestamp: 1.hour.ago.iso8601, properties: { region: "eu-west-1" } }.merge(overrides) }
  end

  describe "POST /api/v1/events" do
    it "accepts an event" do
      post "/api/v1/events", params: event_payload.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(json["status"]).to eq("accepted")
      expect(json.dig("event", "transaction_id")).to eq("txn_1")
      expect(organization.usage_events.count).to eq(1)
    end

    it "answers a replay with the stored event and no new charge" do
      post "/api/v1/events", params: event_payload.to_json, headers: headers
      post "/api/v1/events", params: event_payload.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("duplicate")
      expect(organization.usage_events.count).to eq(1)
    end

    it "explains why an event was rejected" do
      post "/api/v1/events", params: event_payload(external_subscription_id: "nope").to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details").first).to match(/was not found/)
    end

    it "refuses an unauthenticated request" do
      post "/api/v1/events", params: event_payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("unauthorized")
    end

    it "refuses a revoked key" do
      api_key.revoke!

      post "/api/v1/events", params: event_payload.to_json, headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "cannot reach another organization's subscription" do
      other = create(:organization)
      create(:subscription, organization: other, external_id: "sub_other", started_at: 2.months.ago)

      post "/api/v1/events", params: event_payload(external_subscription_id: "sub_other").to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "records when the key was last used" do
      post "/api/v1/events", params: event_payload.to_json, headers: headers

      expect(api_key.reload.last_used_at).to be_present
    end
  end

  describe "POST /api/v1/events/batch" do
    it "reports on each event in the batch" do
      events = [
        { transaction_id: "a", external_subscription_id: subscription.external_id, code: "calls" },
        { transaction_id: "b", external_subscription_id: "missing", code: "calls" }
      ]

      post "/api/v1/events/batch", params: { events: events }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["accepted"]).to eq(1)
      expect(json["rejected"]).to eq(1)
      expect(json["results"].last["errors"].first).to match(/was not found/)
    end

    it "refuses a batch that is too large" do
      events = Array.new(Events::IngestBatch::MAX_EVENTS + 1) do |index|
        { transaction_id: "txn_#{index}", external_subscription_id: subscription.external_id, code: "calls" }
      end

      post "/api/v1/events/batch", params: { events: events }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("batch_too_large")
    end
  end

  describe "GET /api/v1/events" do
    it "lists the most recent events" do
      create(:usage_event, organization: organization, subscription: subscription, code: "calls")

      get "/api/v1/events", headers: headers

      expect(json["events"].length).to eq(1)
    end
  end
end
