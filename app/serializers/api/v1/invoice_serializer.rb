module Api
  module V1
    class InvoiceSerializer
      def initialize(invoice, include_line_items: true)
        @invoice = invoice
        @include_line_items = include_line_items
      end

      def as_json(*)
        payload = {
          id: invoice.id,
          number: invoice.number,
          status: invoice.status,
          currency: invoice.currency,
          external_customer_id: invoice.customer.external_id,
          external_subscription_id: invoice.subscription.external_id,
          period_start: invoice.period_start.utc.iso8601,
          period_end: invoice.period_end.utc.iso8601,
          subtotal_cents: invoice.subtotal_cents,
          tax_rate_bps: invoice.tax_rate_bps,
          tax_cents: invoice.tax_cents,
          total_cents: invoice.total_cents,
          finalized_at: invoice.finalized_at&.utc&.iso8601,
          paid_at: invoice.paid_at&.utc&.iso8601
        }

        return payload unless include_line_items

        payload.merge(line_items: invoice.line_items.map do |item|
          {
            kind: item.kind,
            description: item.description,
            metric_code: item.billable_metric&.code,
            quantity: item.quantity.to_s("F"),
            unit_amount_cents: item.unit_amount_cents,
            amount_cents: item.amount_cents,
            breakdown: item.breakdown
          }
        end)
      end

      private

      attr_reader :invoice, :include_line_items
    end
  end
end
