require "rails_helper"

RSpec.describe Billing::BillingPeriod do
  def subscription_started(iso, interval: "monthly", terminated_at: nil)
    plan = create(:plan, interval: interval)
    create(:subscription, organization: plan.organization, plan: plan,
                          started_at: Time.zone.parse(iso), terminated_at: terminated_at,
                          status: terminated_at ? "terminated" : "active")
  end

  describe ".containing" do
    it "returns the period that holds the time" do
      subscription = subscription_started("2026-03-10 09:00:00 UTC")
      period = described_class.containing(subscription, Time.zone.parse("2026-03-25 12:00:00 UTC"))

      expect(period.starts_at).to eq(Time.zone.parse("2026-03-10 09:00:00 UTC"))
      expect(period.ends_at).to eq(Time.zone.parse("2026-04-10 09:00:00 UTC"))
    end

    it "returns nothing before the subscription started" do
      subscription = subscription_started("2026-03-10 09:00:00 UTC")

      expect(described_class.containing(subscription, Time.zone.parse("2026-03-09 23:59:00 UTC"))).to be_nil
    end

    it "treats the boundary as the start of the next period" do
      subscription = subscription_started("2026-03-10 09:00:00 UTC")
      period = described_class.containing(subscription, Time.zone.parse("2026-04-10 09:00:00 UTC"))

      expect(period.starts_at).to eq(Time.zone.parse("2026-04-10 09:00:00 UTC"))
    end

    # The anchor must not drift: a subscription that starts on the 31st bills
    # on the 28th in February and is back on the 31st in March.
    it "clamps a month end anchor without losing it" do
      subscription = subscription_started("2026-01-31 00:00:00 UTC")

      february = described_class.containing(subscription, Time.zone.parse("2026-02-10 00:00:00 UTC"))
      march = described_class.containing(subscription, Time.zone.parse("2026-03-10 00:00:00 UTC"))

      expect(february.starts_at).to eq(Time.zone.parse("2026-01-31 00:00:00 UTC"))
      expect(february.ends_at).to eq(Time.zone.parse("2026-02-28 00:00:00 UTC"))
      expect(march.starts_at).to eq(Time.zone.parse("2026-02-28 00:00:00 UTC"))
      expect(march.ends_at).to eq(Time.zone.parse("2026-03-31 00:00:00 UTC"))
    end

    it "handles a yearly interval" do
      subscription = subscription_started("2024-02-29 00:00:00 UTC", interval: "yearly")
      period = described_class.containing(subscription, Time.zone.parse("2025-06-01 00:00:00 UTC"))

      expect(period.starts_at).to eq(Time.zone.parse("2025-02-28 00:00:00 UTC"))
      expect(period.ends_at).to eq(Time.zone.parse("2026-02-28 00:00:00 UTC"))
    end
  end

  describe ".closed_periods" do
    it "returns only periods that have fully elapsed" do
      subscription = subscription_started("2026-01-01 00:00:00 UTC")
      periods = described_class.closed_periods(subscription, up_to: Time.zone.parse("2026-03-15 00:00:00 UTC"))

      expect(periods.map { |period| period.starts_at.to_date.to_s }).to eq(%w[2026-01-01 2026-02-01])
    end

    it "returns nothing before the first period closes" do
      subscription = subscription_started("2026-01-01 00:00:00 UTC")

      expect(described_class.closed_periods(subscription, up_to: Time.zone.parse("2026-01-20 00:00:00 UTC"))).to be_empty
    end

    it "closes the part period that a termination cut short" do
      subscription = subscription_started("2026-01-01 00:00:00 UTC",
                                          terminated_at: Time.zone.parse("2026-02-16 00:00:00 UTC"))
      periods = described_class.closed_periods(subscription, up_to: Time.zone.parse("2026-03-01 00:00:00 UTC"))

      expect(periods.length).to eq(2)
      expect(periods.last.ends_at).to eq(Time.zone.parse("2026-02-16 00:00:00 UTC"))
      expect(periods.last).to be_truncated
      expect(periods.last.natural_ends_at).to eq(Time.zone.parse("2026-03-01 00:00:00 UTC"))
    end

    it "does not invent a part period when the termination lands on a boundary" do
      subscription = subscription_started("2026-01-01 00:00:00 UTC",
                                          terminated_at: Time.zone.parse("2026-02-01 00:00:00 UTC"))
      periods = described_class.closed_periods(subscription, up_to: Time.zone.parse("2026-03-01 00:00:00 UTC"))

      expect(periods.length).to eq(1)
      expect(periods.first).not_to be_truncated
    end
  end

  describe "#proration_fraction" do
    it "is one for a whole period" do
      subscription = subscription_started("2026-01-01 00:00:00 UTC")
      period = described_class.containing(subscription, Time.zone.parse("2026-01-15 00:00:00 UTC"))

      expect(period.proration_fraction).to eq(1)
    end

    it "is the elapsed share of a truncated period" do
      subscription = subscription_started("2026-01-01 00:00:00 UTC",
                                          terminated_at: Time.zone.parse("2026-01-16 00:00:00 UTC"))
      period = described_class.closed_periods(subscription, up_to: Time.zone.parse("2026-02-05 00:00:00 UTC")).first

      # 15 of the 31 days in January.
      expect(period.proration_fraction.round(6)).to eq((BigDecimal("15") / 31).round(6))
    end
  end
end
