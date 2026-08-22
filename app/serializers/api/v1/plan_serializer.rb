module Api
  module V1
    class PlanSerializer
      def initialize(plan) = @plan = plan

      def as_json(*)
        {
          code: plan.code,
          name: plan.name,
          description: plan.description,
          currency: plan.currency,
          interval: plan.interval,
          base_amount_cents: plan.base_amount_cents,
          minimum_amount_cents: plan.minimum_amount_cents,
          active: plan.active,
          charges: plan.charges.map do |charge|
            {
              metric_code: charge.billable_metric.code,
              metric_name: charge.billable_metric.name,
              aggregation: charge.billable_metric.aggregation_type,
              pricing_model: charge.pricing_model,
              properties: charge.properties
            }
          end
        }
      end

      private

      attr_reader :plan
    end
  end
end
