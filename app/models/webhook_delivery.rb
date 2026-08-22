class WebhookDelivery < ApplicationRecord
  MAX_ATTEMPTS = 6

  belongs_to :webhook_endpoint

  validates :event_type, presence: true
  validates :status, inclusion: { in: %w[pending delivered failed] }

  scope :due, ->(now = Time.current) { where(status: "pending").where(deliver_after: ..now) }
  scope :recent, -> { order(created_at: :desc) }

  delegate :url, :secret, to: :webhook_endpoint

  def exhausted? = attempts >= MAX_ATTEMPTS

  # 30s, 1m, 2m, 4m, 8m: enough to ride out a receiver restart without
  # hammering an endpoint that is genuinely down.
  def next_backoff = (30 * (2**[ attempts - 1, 0 ].max)).seconds
end
