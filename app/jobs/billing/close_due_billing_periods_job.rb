module Billing
  # Runs nightly. Finds every period that has finished without being invoiced
  # and hands each one to its own job, so one customer with awkward data
  # cannot hold up the rest of the billing run.
  class CloseDueBillingPeriodsJob < ApplicationJob
    queue_as :billing

    def perform(up_to: Time.current)
      enqueued = 0

      Subscription.where(status: %w[active terminated]).find_each do |subscription|
        subscription.closed_billing_periods(up_to: up_to).each do |period|
          next if Invoice.exists?(subscription_id: subscription.id, period_start: period.starts_at)

          GenerateInvoiceJob.perform_later(subscription.id, period.starts_at.utc.iso8601)
          enqueued += 1
        end
      end

      Rails.logger.info("[billing] queued #{enqueued} invoice(s) for periods closed on or before #{up_to.utc.iso8601}")
      enqueued
    end
  end
end
