module Webhooks
  class DeliverJob < ApplicationJob
    queue_as :webhooks

    def perform(delivery_id)
      delivery = WebhookDelivery.find_by(id: delivery_id)
      return if delivery.nil?

      Deliver.call(delivery: delivery)
    end
  end
end
