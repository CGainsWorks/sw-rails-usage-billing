class DashboardController < ApplicationController
  def show
    @organization = current_organization
    @subscription_count = @organization.subscriptions.active.count
    @customer_count = @organization.customers.count
    @events_this_month = @organization.usage_events.where(occurred_at: 30.days.ago..).count
    @outstanding = @organization.invoices.outstanding
    @outstanding_cents = @outstanding.sum(:total_cents)
    @billed_last_90_days_cents = @organization.invoices.finalized.where(finalized_at: 90.days.ago..).sum(:total_cents)
    @recent_invoices = @organization.invoices.includes(:customer).ordered.limit(8)
    @recent_events = @organization.usage_events.includes(subscription: :customer).recent.limit(10)
  end
end
