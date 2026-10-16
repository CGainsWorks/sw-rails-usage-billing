# Receives Stripe's webhooks. The Stripe-Signature header is verified with the
# official library against the endpoint's signing secret before the body is
# parsed and the timestamp in it must be within Stripe's default tolerance of
# five minutes, so a captured request cannot be replayed later.
class StripeWebhooksController < ActionController::API
  SIGNATURE_HEADER = "Stripe-Signature".freeze

  def create
    secret = ENV["STRIPE_WEBHOOK_SECRET"].presence
    return head(:service_unavailable) if secret.nil?

    event = Stripe::Webhook.construct_event(request.raw_post, request.headers[SIGNATURE_HEADER].to_s, secret)
    render json: { received: true, outcome: Payments::StripeWebhookHandler.call(event) }
  rescue Stripe::SignatureVerificationError, JSON::ParserError
    head :bad_request
  end
end
