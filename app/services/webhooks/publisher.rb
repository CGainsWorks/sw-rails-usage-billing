module Webhooks
  class Publisher
    def self.publish(organization:, event_type:, payload:)
      organization.webhook_endpoints.active.find_each do |endpoint|
        delivery = endpoint.webhook_deliveries.create!(
          event_type: event_type,
          payload: { id: SecureRandom.uuid, type: event_type, created_at: Time.current.utc.iso8601, data: payload },
          deliver_after: Time.current
        )

        DeliverJob.perform_later(delivery.id)
      end
    end
  end
end
