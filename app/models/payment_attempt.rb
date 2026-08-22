class PaymentAttempt < ApplicationRecord
  belongs_to :invoice

  validates :status, inclusion: { in: %w[pending succeeded failed] }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :succeeded, -> { where(status: "succeeded") }

  def succeeded? = status == "succeeded"

  def failed? = status == "failed"
end
