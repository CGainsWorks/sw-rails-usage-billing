# An organization is the billing provider itself: the company using Meterly to
# invoice its own customers. Every other record hangs off one.
class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :billable_metrics, dependent: :destroy
  has_many :plans, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :usage_events, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "may only contain lowercase letters, digits and dashes" }
  validates :currency, presence: true, length: { is: 3 }

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase }
end
