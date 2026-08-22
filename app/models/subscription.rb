class Subscription < ApplicationRecord
  STATUSES = %w[active terminated].freeze

  belongs_to :organization
  belongs_to :customer
  belongs_to :plan
  has_many :usage_events, dependent: :destroy
  has_many :invoices, dependent: :restrict_with_error

  validates :external_id, presence: true, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true
  validate :plan_must_belong_to_the_same_organization
  validate :customer_must_belong_to_the_same_organization

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(started_at: :desc) }

  delegate :currency, :interval, to: :plan

  def active? = status == "active"

  def terminated? = status == "terminated"

  def terminate!(at: Time.current)
    update!(status: "terminated", terminated_at: at)
  end

  # The period that contains the given time, or nil when the subscription had
  # not started yet.
  def billing_period_at(time = Time.current)
    Billing::BillingPeriod.containing(self, time)
  end

  def current_billing_period = billing_period_at(Time.current)

  # Every period that has fully elapsed and is therefore ready to invoice.
  def closed_billing_periods(up_to: Time.current)
    Billing::BillingPeriod.closed_periods(self, up_to: up_to)
  end

  private

  def plan_must_belong_to_the_same_organization
    return if plan.blank? || organization_id.blank?

    errors.add(:plan, "must belong to the same organization") if plan.organization_id != organization_id
  end

  def customer_must_belong_to_the_same_organization
    return if customer.blank? || organization_id.blank?

    errors.add(:customer, "must belong to the same organization") if customer.organization_id != organization_id
  end
end
