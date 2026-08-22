module Billing
  # Draft to finalized: assigns the invoice number, tells the outside world,
  # and asks the payment provider for the money.
  class FinalizeInvoice
    def self.call(...) = new(...).call

    def initialize(invoice:)
      @invoice = invoice
    end

    def call
      return invoice unless invoice.draft?

      Invoice.transaction do
        # Numbering has to be gapless per organization, so the sequence is read
        # and written under a transaction-scoped advisory lock rather than
        # relying on a plain COUNT that two workers could read at once.
        lock_numbering
        invoice.update!(status: "finalized", number: next_number, finalized_at: Time.current)
      end

      Webhooks::Publisher.publish(
        organization: invoice.organization,
        event_type: "invoice.finalized",
        payload: Api::V1::InvoiceSerializer.new(invoice.reload).as_json
      )
      Payments::ChargeInvoiceJob.perform_later(invoice.id)

      invoice
    end

    private

    attr_reader :invoice

    def lock_numbering
      Invoice.connection.exec_query("SELECT 1 AS locked FROM pg_advisory_xact_lock($1, $2)", "invoice numbering lock",
                                    [ invoice.organization_id, year ])
    end

    def next_number
      sequence = Invoice.where(organization_id: invoice.organization_id)
                        .where.not(number: nil)
                        .where("number LIKE ?", "#{number_prefix}%")
                        .count + 1

      format("%s%05d", number_prefix, sequence)
    end

    def number_prefix = "INV-#{invoice.organization.slug.upcase}-#{year}-"

    def year = invoice.period_end.year
  end
end
