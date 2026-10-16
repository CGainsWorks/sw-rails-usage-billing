module Payments
  # Copies one accepted usage event to the provider's meter. Only enqueued when
  # Gateway.mirror_usage? is on.
  class MirrorUsageJob < ApplicationJob
    queue_as :payments

    retry_on Gateway::TransientError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveRecord::RecordNotFound

    def perform(usage_event_id)
      gateway = Gateway.current
      return unless gateway.respond_to?(:report_usage)

      gateway.report_usage(UsageEvent.find(usage_event_id))
    end
  end
end
