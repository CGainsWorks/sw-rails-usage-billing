class Plan < ApplicationRecord
  INTERVALS = %w[monthly yearly].freeze

  belongs_to :organization
  has_many :charges, dependent: :destroy
  has_many :subscriptions, dependent: :restrict_with_error
  has_many :billable_metrics, through: :charges

  accepts_nested_attributes_for :charges

  validates :code, presence: true, uniqueness: { scope: :organization_id }
  validates :name, presence: true
  validates :currency, presence: true, length: { is: 3 }
  validates :interval, inclusion: { in: INTERVALS }
  validates :base_amount_cents, :minimum_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :trial_period_days, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:base_amount_cents, :code) }

  def has_minimum? = minimum_amount_cents.positive?
end
