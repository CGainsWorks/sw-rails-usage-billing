# Receives the application's own webhooks so the outbound delivery path can be
# verified over real HTTP. The signature is checked against every active
# endpoint secret, and a receipt is recorded either way.
class WebhookSinkController < ActionController::API
  def create
    body = request.raw_post
    header = request.headers[Webhooks::Signature::HEADER]

    valid = WebhookEndpoint.active.any? do |endpoint|
      Webhooks::Signature.verify(header_value: header, payload: body, secret: endpoint.secret)
    end

    payload = begin
      JSON.parse(body)
    rescue JSON::ParserError
      { "raw" => body }
    end

    WebhookSinkReceipt.create!(
      event_type: payload["type"].presence || "unknown",
      signature_valid: valid,
      payload: payload,
      received_at: Time.current
    )

    head(valid ? :ok : :bad_request)
  end

  def index
    receipts = WebhookSinkReceipt.recent.limit(50)
    receipts = receipts.where(event_type: params[:event_type]) if params[:event_type].present?

    render json: {
      receipts: receipts.map do |receipt|
        {
          event_type: receipt.event_type,
          signature_valid: receipt.signature_valid,
          received_at: receipt.received_at.utc.iso8601,
          payload: receipt.payload
        }
      end
    }
  end
end
