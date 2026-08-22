class SubscriptionsController < ApplicationController
  def show
    @subscription = current_organization.subscriptions.includes(:customer, plan: { charges: :billable_metric }).find(params[:id])
    @statement = Billing::UsagePreview.call(subscription: @subscription)
    @invoices = @subscription.invoices.ordered.limit(12)
    @recent_events = @subscription.usage_events.recent.limit(15)
  end
end
