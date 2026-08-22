module Api
  module V1
    class StatementSerializer
      def initialize(statement) = @statement = statement

      def as_json(*)
        {
          period_start: statement.period.starts_at.utc.iso8601,
          period_end: statement.period.ends_at.utc.iso8601,
          currency: statement.currency,
          subtotal_cents: statement.subtotal_cents,
          tax_rate_bps: statement.tax_rate_bps,
          tax_cents: statement.tax_cents,
          total_cents: statement.total_cents,
          lines: statement.lines.map do |line|
            {
              kind: line.kind,
              description: line.description,
              metric_code: line.billable_metric&.code,
              quantity: line.quantity.to_s("F"),
              amount_cents: line.amount_cents,
              breakdown: line.breakdown
            }
          end
        }
      end

      private

      attr_reader :statement
    end
  end
end
