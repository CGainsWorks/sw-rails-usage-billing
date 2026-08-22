class CustomersController < ApplicationController
  def index
    @customers = current_organization.customers.ordered
  end

  def show
    @customer = current_organization.customers.find(params[:id])
    @subscriptions = @customer.subscriptions.includes(:plan).ordered
    @invoices = @customer.invoices.ordered.limit(20)
  end
end
