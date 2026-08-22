module Api
  module V1
    class PlansController < BaseController
      def index
        plans = current_organization.plans.includes(charges: :billable_metric).ordered
        render json: { plans: plans.map { |plan| PlanSerializer.new(plan).as_json } }
      end

      def show
        plan = current_organization.plans.includes(charges: :billable_metric).find_by!(code: params[:id])
        render json: { plan: PlanSerializer.new(plan).as_json }
      end
    end
  end
end
