module Api
  module V1
    class InvoicesController < BaseController
      def index
        invoices = current_organization.invoices.includes(:customer, :subscription).ordered.limit(pagination_limit)
        invoices = invoices.where(status: params[:status]) if params[:status].present?
        if params[:external_customer_id].present?
          customer = current_organization.customers.find_by!(external_id: params[:external_customer_id])
          invoices = invoices.where(customer_id: customer.id)
        end

        render json: { invoices: invoices.map { |invoice| InvoiceSerializer.new(invoice).as_json } }
      end

      def show
        invoice = current_organization.invoices.includes(line_items: :billable_metric)
        invoice = invoice.find_by(number: params[:id]) || invoice.find(params[:id])

        render json: { invoice: InvoiceSerializer.new(invoice, include_line_items: true).as_json }
      end
    end
  end
end
