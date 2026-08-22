class InvoicesController < ApplicationController
  def index
    @invoices = current_organization.invoices.includes(:customer, :subscription).ordered.limit(100)
    @invoices = @invoices.where(status: params[:status]) if params[:status].present?
  end

  # Finished invoices are addressed by their number, drafts by their id.
  def show
    scope = current_organization.invoices.includes(:customer, :subscription, :payment_attempts, line_items: :billable_metric)
    @invoice = scope.find_by(number: params[:id]) || scope.find(params[:id])
  end
end
