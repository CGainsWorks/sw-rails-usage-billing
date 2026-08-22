module Billing
  # What the current, still-open period would cost if it were invoiced now.
  class UsagePreview
    def self.call(subscription:, at: Time.current)
      period = subscription.billing_period_at(at)
      return nil if period.nil?

      PeriodStatement.call(subscription: subscription, period: period)
    end
  end
end
