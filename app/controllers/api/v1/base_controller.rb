module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::RateLimiting

      # Ingest traffic is machine traffic: one noisy client should not be able
      # to starve the rest of the tenants.
      rate_limit to: 600, within: 1.minute,
                 by: -> { request.headers["Authorization"].presence || request.remote_ip },
                 with: -> { render_error("rate_limited", "too many requests, slow down", status: :too_many_requests) }

      before_action :authenticate!

      rescue_from ActiveRecord::RecordNotFound do |error|
        render_error("not_found", error.message, status: :not_found)
      end

      rescue_from ActionController::ParameterMissing do |error|
        render_error("invalid_request", error.message, status: :unprocessable_content)
      end

      attr_reader :current_organization, :current_api_key

      private

      def authenticate!
        @current_api_key = ApiKey.authenticate(bearer_token)
        return render_error("unauthorized", "a valid API key is required", status: :unauthorized) if @current_api_key.nil?

        @current_organization = @current_api_key.organization
        @current_api_key.touch_usage!
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        return header.split(" ", 2).last if header.start_with?("Bearer ")

        params[:api_key].presence
      end

      def render_error(code, message, status:, details: [])
        render json: { error: { code: code, message: message, details: details } }, status: status
      end

      def render_validation_errors(record)
        render_error("invalid_request", "the record could not be saved", status: :unprocessable_content,
                     details: record.errors.full_messages)
      end

      def pagination_limit(default: 50, max: 200)
        [ params.fetch(:limit, default).to_i, max ].min.clamp(1, max)
      end
    end
  end
end
