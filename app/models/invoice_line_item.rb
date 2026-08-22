class InvoiceLineItem < ApplicationRecord
  KINDS = %w[subscription_fee usage minimum_true_up].freeze

  belongs_to :invoice
  belongs_to :charge, optional: true
  belongs_to :billable_metric, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :description, presence: true

  # Tier-by-tier working for a tiered or volume charge, kept so an invoice can
  # always explain itself long after the prices have changed.
  def tier_breakdown = Array(breakdown["tiers"])

  def prorated? = breakdown["prorated"].present?
end
