# A single metered fact reported by the customer's system: one API call, one
# gigabyte processed, one seat active.
class UsageEvent < ApplicationRecord
  belongs_to :organization
  belongs_to :subscription

  validates :transaction_id, presence: true, uniqueness: { scope: :organization_id }
  validates :code, presence: true
  validates :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }
  scope :for_code, ->(code) { where(code: code) }
  scope :between, ->(from, to) { where(occurred_at: from...to) }
end
