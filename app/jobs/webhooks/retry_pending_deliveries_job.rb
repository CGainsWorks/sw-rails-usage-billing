module Webhooks
  # Deliveries that failed are left in the database with a deliver_after in the
  # future rather than sitting in the job backend, so a receiver that is down
  # for an hour costs one row per event and not one retrying job per event.
  class RetryPendingDeliveriesJob < ApplicationJob
    queue_as :webhooks

    def perform(now: Time.current)
      WebhookDelivery.due(now).find_each do |delivery|
        DeliverJob.perform_later(delivery.id)
      end
    end
  end
end
