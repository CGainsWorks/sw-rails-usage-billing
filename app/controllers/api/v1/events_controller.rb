module Api
  module V1
    class EventsController < BaseController
      # POST /api/v1/events
      def create
        result = Events::Ingest.call(organization: current_organization, attributes: event_params)

        if result.success?
          render json: { status: result.status, event: EventSerializer.new(result.event).as_json },
                 status: result.duplicate ? :ok : :created
        else
          render_error("invalid_event", "the event was rejected", status: :unprocessable_content, details: result.errors)
        end
      end

      # POST /api/v1/events/batch
      def batch
        events = params.require(:events)
        if events.length > Events::IngestBatch::MAX_EVENTS
          return render_error("batch_too_large", "at most #{Events::IngestBatch::MAX_EVENTS} events per batch",
                              status: :unprocessable_content)
        end

        summary = Events::IngestBatch.call(organization: current_organization, events: events.map { |event| permit_event(event) })

        render json: summary.to_h.merge(
          results: summary.results.map.with_index do |result, index|
            { index: index, status: result.status, errors: result.errors, transaction_id: result.event&.transaction_id }
          end
        )
      end

      # GET /api/v1/events
      def index
        events = current_organization.usage_events.recent.limit(pagination_limit)
        events = events.for_code(params[:code]) if params[:code].present?

        render json: { events: events.map { |event| EventSerializer.new(event).as_json } }
      end

      private

      def event_params = permit_event(params.require(:event))

      def permit_event(event)
        ActionController::Parameters.new(event.to_unsafe_h)
                                   .permit(:transaction_id, :external_subscription_id, :code, :timestamp, properties: {})
      end
    end
  end
end
