module Payments
  # Charges a finalized invoice and records the attempt either way.
  class Collect
    def self.call(...) = new(...).call

    def initialize(invoice:, gateway: Gateway.current)
      @invoice = invoice
      @gateway = gateway
    end

    def call
      return nil unless invoice.finalized?

      result = gateway.charge(invoice)
      attempt = record(result)

      if result.success?
        invoice.update!(status: "paid", paid_at: Time.current)
        publish("invoice.paid")
      else
        publish("invoice.payment_failed")
      end

      attempt
    end

    private

    attr_reader :invoice, :gateway

    def record(result)
      invoice.payment_attempts.create!(
        provider: gateway.provider,
        provider_reference: result.reference,
        amount_cents: invoice.total_cents,
        currency: invoice.currency,
        status: result.success? ? "succeeded" : "failed",
        failure_reason: result.failure_reason,
        processed_at: Time.current
      )
    end

    def publish(event_type)
      Webhooks::Publisher.publish(
        organization: invoice.organization,
        event_type: event_type,
        payload: Api::V1::InvoiceSerializer.new(invoice.reload).as_json
      )
    end
  end
end
