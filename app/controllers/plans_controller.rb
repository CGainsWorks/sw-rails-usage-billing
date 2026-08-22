class PlansController < ApplicationController
  def index
    @plans = current_organization.plans.includes(charges: :billable_metric).ordered
  end

  def show
    @plan = current_organization.plans.includes(charges: :billable_metric).find(params[:id])
    @subscriptions = @plan.subscriptions.includes(:customer).ordered.limit(20)
  end
end
