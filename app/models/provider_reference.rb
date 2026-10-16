# One Meterly record's identity at a payment provider: the Stripe customer for
# a Customer, the Billing Meter for a BillableMetric, the Price for a Charge and
# so on. Kept in its own table so the billing engine never grows provider
# columns.
class ProviderReference < ApplicationRecord
  KINDS = %w[customer product meter price invoice].freeze

  belongs_to :record, polymorphic: true

  validates :provider, :external_id, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :kind, uniqueness: { scope: %i[provider record_type record_id] }

  def self.external_id_for(provider:, record:, kind:)
    find_by(provider: provider, record: record, kind: kind)&.external_id
  end

  def self.record_for(provider:, kind:, external_id:)
    find_by(provider: provider, kind: kind, external_id: external_id)&.record
  end
end
