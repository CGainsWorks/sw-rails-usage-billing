module Api
  module V1
    class EventSerializer
      def initialize(event) = @event = event

      def as_json(*)
        {
          transaction_id: event.transaction_id,
          external_subscription_id: event.subscription.external_id,
          code: event.code,
          timestamp: event.occurred_at.utc.iso8601,
          properties: event.properties,
          received_at: event.created_at.utc.iso8601
        }
      end

      private

      attr_reader :event
    end
  end
end
