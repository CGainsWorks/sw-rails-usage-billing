class WebhookEndpoint < ApplicationRecord
  belongs_to :organization
  has_many :webhook_deliveries, dependent: :destroy

  validates :url, presence: true
  validates :secret, presence: true
  validate :url_must_be_http

  scope :active, -> { where(active: true) }

  before_validation :assign_secret, on: :create

  private

  def assign_secret
    self.secret = "whsec_#{SecureRandom.alphanumeric(32)}" if secret.blank?
  end

  def url_must_be_http
    return if url.blank?

    parsed = URI.parse(url)
    errors.add(:url, "must be an http or https URL") unless parsed.is_a?(URI::HTTP) && parsed.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  end
end
