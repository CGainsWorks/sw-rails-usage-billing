module Payments
  # Applies a verified Stripe event to Meterly. The controller has already
  # checked the signature; this only decides what the event means.
  #
  # Stripe delivers at least once and not in order, so every branch is safe to
  # run twice: a paid invoice stays paid and a failure is recorded once per
  # Stripe event id.
  class StripeWebhookHandler
    HANDLED_TYPES = %w[invoice.paid invoice.payment_failed].freeze

    def self.call(...) = new(...).call

    def initialize(event)
      @event = event
    end

    # @return [String] what happened, echoed back to Stripe for the dashboard log
    def call
      return "ignored" unless HANDLED_TYPES.include?(event.type)

      invoice = local_invoice
      return "unknown_invoice" if invoice.nil?

      case event.type
      when "invoice.paid" then mark_paid(invoice)
      when "invoice.payment_failed" then record_failure(invoice)
      end
    end

    private

    attr_reader :event

    def stripe_invoice = event.data.object

    def local_invoice
      by_reference = ProviderReference.record_for(provider: StripeGateway::PROVIDER, kind: "invoice",
                                                  external_id: stripe_invoice.id)
      return by_reference if by_reference

      # An invoice Meterly mirrored but whose reference was never stored, for
      # example because the worker died between Stripe answering and the
      # commit. Trust the metadata only when nothing else claims the invoice.
      meterly_id = stripe_invoice.respond_to?(:metadata) && stripe_invoice.metadata&.[](:meterly_invoice_id)
      candidate = Invoice.find_by(id: meterly_id) if meterly_id.present?
      return nil if candidate.nil?
      return nil if ProviderReference.external_id_for(provider: StripeGateway::PROVIDER, record: candidate, kind: "invoice")

      candidate
    end

    def mark_paid(invoice)
      return "already_paid" if invoice.paid?
      return "not_finalized" unless invoice.finalized?

      Invoice.transaction do
        record_attempt(invoice, status: "succeeded", reference: stripe_invoice.id)
        invoice.update!(status: "paid", paid_at: Time.current)
      end
      publish(invoice, "invoice.paid")
      "marked_paid"
    end

    def record_failure(invoice)
      return "already_paid" if invoice.paid?
      return "duplicate" if invoice.payment_attempts.exists?(provider_reference: event.id)

      record_attempt(invoice, status: "failed", reference: event.id, failure_reason: "payment_failed")
      publish(invoice, "invoice.payment_failed")
      "recorded_failure"
    end

    def record_attempt(invoice, status:, reference:, failure_reason: nil)
      invoice.payment_attempts.create!(
        provider: StripeGateway::PROVIDER,
        provider_reference: reference,
        amount_cents: invoice.total_cents,
        currency: invoice.currency,
        status: status,
        failure_reason: failure_reason,
        processed_at: Time.current
      )
    end

    def publish(invoice, event_type)
      Webhooks::Publisher.publish(
        organization: invoice.organization,
        event_type: event_type,
        payload: Api::V1::InvoiceSerializer.new(invoice.reload).as_json
      )
    end
  end
end
