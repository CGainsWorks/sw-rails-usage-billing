module Billing
  # Billing periods are anchored to the moment a subscription started, so a
  # subscription that began on the 31st of January bills on the 28th of
  # February, the 31st of March and so on, without the anchor drifting to the
  # 28th for good. ActiveSupport::Duration#advance already clamps that way, so
  # every boundary is computed from the anchor rather than from the previous
  # boundary.
  class BillingPeriod
    MAX_PERIODS = 1_200

    attr_reader :subscription, :starts_at, :ends_at, :natural_ends_at

    def initialize(subscription, starts_at, ends_at, natural_ends_at: nil)
      @subscription = subscription
      @starts_at = starts_at
      @ends_at = ends_at
      @natural_ends_at = natural_ends_at || ends_at
    end

    class << self
      def containing(subscription, time)
        return nil if time < subscription.started_at

        index = index_for(subscription, time)
        new(subscription, boundary(subscription, index), boundary(subscription, index + 1))
      end

      # Every period that can be invoiced: the ones that have fully elapsed,
      # plus the part-period that a termination cut short.
      def closed_periods(subscription, up_to: Time.current)
        limit = [ up_to, subscription.terminated_at || up_to ].min
        periods = []
        index = 0

        while index < MAX_PERIODS
          starts_at = boundary(subscription, index)
          break if starts_at >= limit

          natural_end = boundary(subscription, index + 1)

          if natural_end <= limit
            periods << new(subscription, starts_at, natural_end)
          else
            terminated_at = subscription.terminated_at
            if terminated_at && terminated_at <= up_to && terminated_at > starts_at
              periods << new(subscription, starts_at, terminated_at, natural_ends_at: natural_end)
            end
            break
          end

          index += 1
        end

        periods
      end

      def boundary(subscription, index)
        subscription.started_at.advance(months: index * months_per_interval(subscription))
      end

      def months_per_interval(subscription) = subscription.interval == "yearly" ? 12 : 1

      private

      def index_for(subscription, time)
        anchor = subscription.started_at
        step = months_per_interval(subscription)
        index = (((time.year * 12) + time.month) - ((anchor.year * 12) + anchor.month)) / step
        index = 0 if index.negative?

        index -= 1 while index.positive? && boundary(subscription, index) > time
        index += 1 while boundary(subscription, index + 1) <= time
        index
      end
    end

    def range = starts_at...ends_at

    def cover?(time) = time >= starts_at && time < ends_at

    def truncated? = ends_at != natural_ends_at

    def seconds = ends_at - starts_at

    def natural_seconds = natural_ends_at - starts_at

    def days = (seconds / 1.day.to_f).round(4)

    # What share of the recurring fee a truncated period earns.
    def proration_fraction
      return BigDecimal(1) unless truncated?

      BigDecimal(seconds.to_s) / BigDecimal(natural_seconds.to_s)
    end

    def to_s = "#{starts_at.utc.iso8601} -> #{ends_at.utc.iso8601}"

    def ==(other)
      other.is_a?(BillingPeriod) && other.subscription == subscription &&
        other.starts_at == starts_at && other.ends_at == ends_at
    end
    alias eql? ==

    def hash = [ subscription&.id, starts_at, ends_at ].hash
  end
end
