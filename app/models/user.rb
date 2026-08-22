class User < ApplicationRecord
  ROLES = %w[member admin].freeze

  has_secure_password

  belongs_to :organization

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: ROLES }

  normalizes :email_address, with: ->(email) { email.to_s.strip.downcase }

  def admin? = role == "admin"
end
