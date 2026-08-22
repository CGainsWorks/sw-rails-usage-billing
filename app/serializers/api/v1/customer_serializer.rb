module Api
  module V1
    class CustomerSerializer
      def initialize(customer) = @customer = customer

      def as_json(*)
        {
          external_id: customer.external_id,
          name: customer.name,
          email: customer.email,
          currency: customer.currency,
          tax_rate_bps: customer.tax_rate_bps,
          billing_address: customer.billing_address,
          created_at: customer.created_at.utc.iso8601
        }
      end

      private

      attr_reader :customer
    end
  end
end
