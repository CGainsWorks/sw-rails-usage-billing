# Examples tagged :stripe_mock talk to a real stripe-mock server over HTTP
# through the official stripe gem. stripe-mock is Stripe's own API emulator: it
# validates every request against Stripe's OpenAPI specification and answers
# with fixture objects, so a passing example proves the request shape is one
# Stripe accepts. It is stateless and never declines a card, which is why the
# decline examples inject the error at the client.
#
# CI runs the pinned stripe/stripe-mock image as a service container. Locally:
#
#   docker run --rm -p 12111:12111 stripe/stripe-mock:v0.206.0
#   STRIPE_MOCK_URL=http://localhost:12111 bundle exec rspec
module StripeMockHelpers
  def self.url = ENV["STRIPE_MOCK_URL"].presence

  # A fresh throwaway key per run. stripe-mock accepts any sk_test_ key and no
  # real key is ever committed or needed.
  def stripe_mock_client
    Stripe::StripeClient.new("sk_test_#{SecureRandom.hex(12)}", api_base: StripeMockHelpers.url)
  end
end

RSpec.configure do |config|
  config.include StripeMockHelpers, :stripe_mock

  config.before(:each, :stripe_mock) do
    next if StripeMockHelpers.url

    raise "STRIPE_MOCK_URL must be set in CI so the Stripe gateway is exercised" if ENV["CI"].present?

    skip "set STRIPE_MOCK_URL to run against stripe-mock"
  end
end
