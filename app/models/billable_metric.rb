# What gets counted, and how. A metric turns a stream of raw usage events into
# a single number for a billing period.
class BillableMetric < ApplicationRecord
  AGGREGATION_TYPES = %w[count sum max unique_count].freeze
  PROPERTY_AGGREGATIONS = %w[sum max unique_count].freeze

  belongs_to :organization
  has_many :charges, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: { scope: :organization_id },
                   format: { with: /\A[a-z0-9_]+\z/, message: "may only contain lowercase letters, digits and underscores" }
  validates :name, presence: true
  validates :aggregation_type, inclusion: { in: AGGREGATION_TYPES }
  validates :property_name, presence: true, if: :property_based?
  validate :filters_must_be_lists_of_scalars

  scope :ordered, -> { order(:code) }

  def property_based? = aggregation_type.in?(PROPERTY_AGGREGATIONS)

  # A filter narrows the events a metric sees, for example
  # { "region" => ["eu-west-1"] } bills only European traffic.
  def filters_hash = (filters || {}).transform_values { |values| Array(values).map(&:to_s) }

  def aggregation_description
    case aggregation_type
    when "count" then "count of events"
    when "sum" then "sum of #{property_name}"
    when "max" then "peak #{property_name}"
    when "unique_count" then "unique values of #{property_name}"
    end
  end

  private

  def filters_must_be_lists_of_scalars
    return if filters.blank?
    return errors.add(:filters, "must be an object") unless filters.is_a?(Hash)

    filters.each_value do |values|
      next if Array(values).all? { |value| value.is_a?(String) || value.is_a?(Numeric) || [ true, false ].include?(value) }

      errors.add(:filters, "values must be scalars or lists of scalars")
    end
  end
end
