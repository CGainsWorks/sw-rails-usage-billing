# One priced metric inside a plan: "API requests, charged in graduated tiers".
class Charge < ApplicationRecord
  belongs_to :plan
  belongs_to :billable_metric

  validates :pricing_model, inclusion: { in: Billing::PricingModels::NAMES }
  validate :properties_must_be_valid_for_pricing_model

  delegate :code, :aggregation_type, to: :billable_metric, prefix: true

  def pricing = Billing::PricingModels.build(pricing_model, properties)

  def display_name = invoice_display_name.presence || billable_metric.name

  private

  def properties_must_be_valid_for_pricing_model
    return unless pricing_model.in?(Billing::PricingModels::NAMES)

    pricing.validation_errors.each { |message| errors.add(:properties, message) }
  end
end
