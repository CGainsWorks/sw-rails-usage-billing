module Billing
  class GenerateInvoiceJob < ApplicationJob
    queue_as :billing

    # Two workers can pick up the same subscription and period; the unique
    # index decides which one wins and the loser finds the winner's invoice.
    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

    def perform(subscription_id, period_start_iso)
      subscription = Subscription.find(subscription_id)
      period_start = Time.zone.parse(period_start_iso)
      period = subscription.closed_billing_periods(up_to: Time.current).find { |candidate| candidate.starts_at == period_start }

      if period.nil?
        Rails.logger.warn("[billing] subscription #{subscription_id} has no closed period starting #{period_start_iso}")
        return nil
      end

      invoice = GenerateInvoice.call(subscription: subscription, period: period)
      FinalizeInvoice.call(invoice: invoice)
    end
  end
end
