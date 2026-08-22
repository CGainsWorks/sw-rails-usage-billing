module Payments
  # TODO: implement against Stripe PaymentIntents once there is a merchant
  # account to test with. The shape is deliberately the same as
  # SimulatedGateway so only this file changes:
  #
  #   intent = Stripe::PaymentIntent.create(
  #     amount: invoice.total_cents, currency: invoice.currency.downcase,
  #     customer: invoice.customer.metadata["stripe_customer_id"],
  #     confirm: true, off_session: true,
  #     idempotency_key: "invoice-#{invoice.id}-#{invoice.finalized_at.to_i}"
  #   )
  #
  # The idempotency key matters: a retried job must not charge the card twice.
  class StripeGateway
    PROVIDER = "stripe".freeze

    def provider = PROVIDER

    def charge(_invoice)
      raise NotImplementedError, "the Stripe gateway is a stub, see docs/limitations.md"
    end
  end
end
