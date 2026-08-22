class Invoice < ApplicationRecord
  STATUSES = %w[draft finalized paid void].freeze

  belongs_to :organization
  belongs_to :customer
  belongs_to :subscription
  has_many :line_items, -> { order(:position, :id) }, class_name: "InvoiceLineItem", dependent: :destroy
  has_many :payment_attempts, -> { order(created_at: :desc) }, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :currency, presence: true, length: { is: 3 }
  validates :period_start, :period_end, presence: true
  validates :number, uniqueness: { scope: :organization_id }, allow_nil: true

  scope :ordered, -> { order(period_start: :desc, id: :desc) }
  scope :finalized, -> { where(status: %w[finalized paid]) }
  scope :outstanding, -> { where(status: "finalized") }

  def draft? = status == "draft"

  def finalized? = status == "finalized"

  def paid? = status == "paid"

  def void? = status == "void"

  def editable? = draft?

  def period = Billing::BillingPeriod.new(subscription, period_start, period_end)

  def usage_line_items = line_items.select { |item| item.kind == "usage" }

  def to_param = number.presence || id.to_s
end
