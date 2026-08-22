module Api
  module V1
    class SubscriptionsController < BaseController
      def index
        subscriptions = current_organization.subscriptions.includes(:customer, :plan).ordered.limit(pagination_limit)
        render json: { subscriptions: subscriptions.map { |subscription| SubscriptionSerializer.new(subscription).as_json } }
      end

      def show
        render json: { subscription: SubscriptionSerializer.new(find_subscription).as_json }
      end

      def create
        customer = current_organization.customers.find_by!(external_id: subscription_params[:external_customer_id])
        plan = current_organization.plans.find_by!(code: subscription_params[:plan_code])

        subscription = current_organization.subscriptions.new(
          customer: customer,
          plan: plan,
          external_id: subscription_params[:external_id],
          started_at: subscription_params[:started_at].presence || Time.current
        )

        if subscription.save
          render json: { subscription: SubscriptionSerializer.new(subscription).as_json }, status: :created
        else
          render_validation_errors(subscription)
        end
      end

      # Terminating closes the part-period immediately, which is what the
      # nightly billing run will then invoice, prorated.
      def terminate
        subscription = find_subscription
        subscription.terminate! if subscription.active?

        render json: { subscription: SubscriptionSerializer.new(subscription).as_json }
      end

      # The invoice this period would produce if it were closed right now.
      def current_usage
        subscription = find_subscription
        statement = Billing::UsagePreview.call(subscription: subscription)

        if statement.nil?
          return render_error("not_started", "the subscription has not started yet", status: :unprocessable_content)
        end

        render json: { current_usage: StatementSerializer.new(statement).as_json }
      end

      private

      def find_subscription
        current_organization.subscriptions.includes(:customer, :plan).find_by!(external_id: params[:id])
      end

      def subscription_params
        params.require(:subscription).permit(:external_id, :external_customer_id, :plan_code, :started_at)
      end
    end
  end
end
