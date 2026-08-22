FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    sequence(:slug) { |n| "org-#{n}" }
    currency { "GBP" }
  end

  factory :user do
    organization
    sequence(:email_address) { |n| "operator#{n}@meterly.test" }
    name { "Test Operator" }
    password { "password123" }
    role { "admin" }
  end

  factory :api_key do
    organization
    sequence(:name) { |n| "Key #{n}" }
    token_digest { ApiKey.digest("mtr_sk_#{SecureRandom.alphanumeric(32)}") }
    token_prefix { "mtr_sk_test" }
  end

  factory :billable_metric do
    organization
    sequence(:code) { |n| "metric_#{n}" }
    name { "Metric" }
    aggregation_type { "count" }
  end

  factory :plan do
    organization
    sequence(:code) { |n| "plan_#{n}" }
    name { "Plan" }
    currency { "GBP" }
    interval { "monthly" }
    base_amount_cents { 0 }
  end

  factory :charge do
    plan
    billable_metric { association :billable_metric, organization: plan.organization }
    pricing_model { "per_unit" }
    properties { { "unit_amount_cents" => 10 } }
  end

  factory :customer do
    organization
    sequence(:external_id) { |n| "cus_#{n}" }
    name { "Customer" }
    currency { "GBP" }
  end

  factory :subscription do
    organization
    customer { association :customer, organization: organization }
    plan { association :plan, organization: organization }
    sequence(:external_id) { |n| "sub_#{n}" }
    started_at { 2.months.ago }
    status { "active" }
  end

  factory :usage_event do
    subscription
    organization { subscription.organization }
    sequence(:transaction_id) { |n| "txn_#{n}" }
    code { "metric" }
    occurred_at { Time.current }
    properties { {} }
  end

  factory :webhook_endpoint do
    organization
    url { "https://receiver.test/hooks" }
  end
end
