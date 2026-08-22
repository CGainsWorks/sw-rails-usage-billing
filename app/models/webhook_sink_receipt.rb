class WebhookSinkReceipt < ApplicationRecord
  scope :recent, -> { order(received_at: :desc) }
  scope :valid_signature, -> { where(signature_valid: true) }
end
