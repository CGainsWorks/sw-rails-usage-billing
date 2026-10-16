module Events
  # Accepts one metered event. Everything the caller can get wrong is caught
  # here, because an event that is silently dropped becomes revenue that is
  # silently lost.
  class Ingest
    FUTURE_TOLERANCE = 5.minutes

    Result = Data.define(:event, :duplicate, :errors) do
      def success? = errors.empty?

      def status = success? ? (duplicate ? "duplicate" : "accepted") : "rejected"
    end

    def self.call(...) = new(...).call

    def initialize(organization:, attributes:)
      @organization = organization
      @attributes = (attributes || {}).to_h.deep_stringify_keys
    end

    def call
      errors = validate
      return Result.new(event: nil, duplicate: false, errors: errors) if errors.any?

      event = create_event
      # Only a newly stored event is mirrored, so a replay never reaches the
      # provider twice.
      Payments::MirrorUsageJob.perform_later(event.id) if Payments::Gateway.mirror_usage?
      Result.new(event: event, duplicate: false, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      # The uniqueness validation and the unique index can both catch a replay,
      # depending on whether the first copy was committed yet.
      return Result.new(event: existing_event, duplicate: true, errors: []) if existing_event

      Result.new(event: nil, duplicate: false, errors: e.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      Result.new(event: existing_event, duplicate: true, errors: [])
    end

    private

    attr_reader :organization, :attributes

    def validate
      errors = []
      errors << "transaction_id is required" if transaction_id.blank?
      errors << "code is required" if code.blank?
      errors << "subscription #{external_subscription_id.inspect} was not found" if subscription.nil?
      errors << "no billable metric with code #{code.inspect}" if code.present? && metric.nil?
      errors << "timestamp is not a valid time" if raw_timestamp.present? && occurred_at.nil?
      return errors if errors.any?

      errors << "timestamp is more than #{FUTURE_TOLERANCE.inspect} in the future" if occurred_at > FUTURE_TOLERANCE.from_now
      errors << "timestamp is before the subscription started" if occurred_at < subscription.started_at
      if subscription.terminated_at && occurred_at >= subscription.terminated_at
        errors << "timestamp is after the subscription was terminated"
      end
      errors
    end

    def create_event
      UsageEvent.create!(
        organization: organization,
        subscription: subscription,
        transaction_id: transaction_id,
        code: code,
        occurred_at: occurred_at,
        properties: properties
      )
    end

    def existing_event
      organization.usage_events.find_by(transaction_id: transaction_id)
    end

    def transaction_id = attributes["transaction_id"].presence

    def code = attributes["code"].presence

    def external_subscription_id = attributes["external_subscription_id"].presence

    def properties = attributes["properties"].is_a?(Hash) ? attributes["properties"] : {}

    def raw_timestamp = attributes["timestamp"]

    def subscription
      return @subscription if defined?(@subscription)

      @subscription = organization.subscriptions.find_by(external_id: external_subscription_id)
    end

    def metric
      return @metric if defined?(@metric)

      @metric = organization.billable_metrics.find_by(code: code)
    end

    def occurred_at
      return @occurred_at if defined?(@occurred_at)

      @occurred_at = parse_timestamp
    end

    # Accepts an ISO 8601 string or epoch seconds, because SDKs in the wild
    # send both.
    def parse_timestamp
      value = raw_timestamp
      return Time.current if value.blank?
      return Time.zone.at(value) if value.is_a?(Numeric)
      return Time.zone.at(Float(value)) if value.to_s.match?(/\A\d+(\.\d+)?\z/)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
