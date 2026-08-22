class Customer < ApplicationRecord
  belongs_to :organization
  has_many :subscriptions, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error

  validates :external_id, presence: true, uniqueness: { scope: :organization_id }
  validates :name, presence: true
  validates :currency, presence: true, length: { is: 3 }
  validates :tax_rate_bps, numericality: { in: 0..10_000 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  normalizes :email, with: ->(email) { email.to_s.strip.downcase.presence }

  scope :ordered, -> { order(:name) }

  def tax_rate_percentage = (tax_rate_bps / 100.0).round(2)
end
