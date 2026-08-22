module Api
  module V1
    class SubscriptionSerializer
      def initialize(subscription) = @subscription = subscription

      def as_json(*)
        period = subscription.current_billing_period

        {
          external_id: subscription.external_id,
          status: subscription.status,
          external_customer_id: subscription.customer.external_id,
          plan_code: subscription.plan.code,
          currency: subscription.currency,
          started_at: subscription.started_at.utc.iso8601,
          terminated_at: subscription.terminated_at&.utc&.iso8601,
          current_period_start: period&.starts_at&.utc&.iso8601,
          current_period_end: period&.ends_at&.utc&.iso8601
        }
      end

      private

      attr_reader :subscription
    end
  end
end
