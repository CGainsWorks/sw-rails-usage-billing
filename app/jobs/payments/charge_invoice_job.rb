module Payments
  class ChargeInvoiceJob < ApplicationJob
    queue_as :payments

    # The gateways use idempotency keys derived from the invoice, so a retry
    # after a timeout replays the same request rather than charging twice.
    retry_on Gateway::TransientError, wait: :polynomially_longer, attempts: 5

    def perform(invoice_id)
      invoice = Invoice.find(invoice_id)
      Collect.call(invoice: invoice)
    end
  end
end
