module Payments
  # Stands in for a card processor. It is deterministic on purpose: a customer
  # whose external id starts with "decline_" always fails, so the dunning path
  # can be demonstrated and tested without a sandbox account.
  class SimulatedGateway
    PROVIDER = "simulated".freeze
    DECLINE_PREFIX = "decline_".freeze

    def provider = PROVIDER

    def charge(invoice)
      if invoice.customer.external_id.to_s.start_with?(DECLINE_PREFIX)
        return Gateway::Result.new(success: false, reference: nil, failure_reason: "card_declined")
      end

      if invoice.total_cents.zero?
        return Gateway::Result.new(success: true, reference: "sim_zero_#{invoice.id}", failure_reason: nil)
      end

      Gateway::Result.new(success: true, reference: "sim_#{SecureRandom.hex(8)}", failure_reason: nil)
    end
  end
end
