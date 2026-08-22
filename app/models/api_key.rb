# API keys authenticate machine traffic on /api/v1.
#
# The digest is SHA-256 rather than bcrypt on purpose. A key arrives on every
# ingest request, so verification has to be a single indexed lookup; bcrypt
# would force a full table scan plus one KDF per candidate row. The token has
# 190 bits of entropy from a CSPRNG, so it needs no stretching against
# dictionary attacks the way a human-chosen password would.
class ApiKey < ApplicationRecord
  TOKEN_PREFIX = "mtr_sk_".freeze

  belongs_to :organization

  validates :name, presence: true, uniqueness: { scope: :organization_id }

  scope :active, -> { where(revoked_at: nil) }

  # Only populated on the instance returned by .issue!, never read back later.
  attr_reader :token

  def self.issue!(organization:, name:)
    token = "#{TOKEN_PREFIX}#{SecureRandom.alphanumeric(32)}"

    key = create!(
      organization: organization,
      name: name,
      token_digest: digest(token),
      token_prefix: token.first(TOKEN_PREFIX.length + 4)
    )
    key.instance_variable_set(:@token, token)
    key
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def self.authenticate(token)
    return nil if token.blank?

    active.find_by(token_digest: digest(token))
  end

  def revoked? = revoked_at.present?

  def revoke! = update!(revoked_at: Time.current)

  def touch_usage!
    # Written at most once a minute so ingest traffic does not turn every
    # request into a write to the same row.
    return if last_used_at.present? && last_used_at > 1.minute.ago

    update_column(:last_used_at, Time.current)
  end
end
