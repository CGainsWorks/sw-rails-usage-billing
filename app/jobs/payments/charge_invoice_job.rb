module Payments
  class ChargeInvoiceJob < ApplicationJob
    queue_as :payments

    def perform(invoice_id)
      invoice = Invoice.find(invoice_id)
      Collect.call(invoice: invoice)
    end
  end
end
