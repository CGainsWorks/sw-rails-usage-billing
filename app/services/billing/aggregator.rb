module Billing
  # Turns the raw events of one metric over one period into a single quantity.
  # The work happens in PostgreSQL: a billing period can hold millions of
  # events and none of them need to travel to Ruby.
  class Aggregator
    NUMERIC_PATTERN = '^-?[0-9]+(\.[0-9]+)?$'.freeze

    # The property name reaches SQL as a bind parameter, never as string
    # interpolation, so a metric called "1); drop table invoices; --" is just an
    # unusual property name.
    AGGREGATE_SQL = {
      "sum" => "COALESCE(SUM((properties ->> ?)::numeric), 0)",
      "max" => "COALESCE(MAX((properties ->> ?)::numeric), 0)"
    }.freeze

    def self.call(...) = new(...).call

    def initialize(subscription:, metric:, period:)
      @subscription = subscription
      @metric = metric
      @period = period
    end

    # @return [BigDecimal]
    def call
      case metric.aggregation_type
      when "count" then BigDecimal(scope.count)
      when "sum", "max" then numeric_aggregate(metric.aggregation_type)
      when "unique_count" then BigDecimal(scope.distinct.count(property_expression))
      else raise ArgumentError, "unsupported aggregation #{metric.aggregation_type.inspect}"
      end
    end

    private

    attr_reader :subscription, :metric, :period

    def scope
      relation = subscription.usage_events
                             .for_code(metric.code)
                             .between(period.starts_at, period.ends_at)

      metric.filters_hash.each do |property, values|
        next if values.empty?

        relation = relation.where("properties ->> ? IN (?)", property, values)
      end

      relation
    end

    def numeric_aggregate(aggregation)
      # A property that is not a number is skipped rather than blowing up the
      # whole invoice run: bad data from one client should not stop billing.
      value = scope
                .where("properties ->> ? ~ ?", metric.property_name, NUMERIC_PATTERN)
                .pick(expression(AGGREGATE_SQL.fetch(aggregation)))

      BigDecimal(value.to_s)
    end

    def property_expression = expression("properties ->> ?")

    def expression(template)
      Arel.sql(template, metric.property_name)
    end
  end
end
