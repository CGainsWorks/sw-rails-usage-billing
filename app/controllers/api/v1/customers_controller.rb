module Api
  module V1
    class CustomersController < BaseController
      def index
        customers = current_organization.customers.ordered.limit(pagination_limit)
        render json: { customers: customers.map { |customer| CustomerSerializer.new(customer).as_json } }
      end

      def show
        render json: { customer: CustomerSerializer.new(find_customer).as_json }
      end

      # Upsert, so a client that retries a create does not get a 422.
      def create
        customer = current_organization.customers.find_or_initialize_by(external_id: customer_params[:external_id])
        created = customer.new_record?
        customer.assign_attributes(customer_params.except(:external_id))
        customer.currency = current_organization.currency if customer.currency.blank?

        if customer.save
          render json: { customer: CustomerSerializer.new(customer).as_json }, status: created ? :created : :ok
        else
          render_validation_errors(customer)
        end
      end

      private

      def find_customer = current_organization.customers.find_by!(external_id: params[:id])

      def customer_params
        params.require(:customer).permit(:external_id, :name, :email, :currency, :tax_rate_bps, billing_address: {})
      end
    end
  end
end
