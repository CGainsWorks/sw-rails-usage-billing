class UsageEventsController < ApplicationController
  PAGE_SIZE = 50

  def index
    @events = current_organization.usage_events.includes(subscription: :customer).recent.limit(PAGE_SIZE)
    @events = @events.for_code(params[:code]) if params[:code].present?
    @codes = current_organization.billable_metrics.ordered.pluck(:code)
  end
end
