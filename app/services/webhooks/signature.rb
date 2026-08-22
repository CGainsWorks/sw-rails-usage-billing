module Webhooks
  # Signs outbound webhooks the way Stripe does: the timestamp is inside the
  # signed payload, so a captured request cannot be replayed later against a
  # receiver that checks the tolerance.
  module Signature
    HEADER = "X-Meterly-Signature".freeze
    TOLERANCE = 5.minutes

    def self.header(payload:, secret:, timestamp: Time.current)
      "t=#{timestamp.to_i},v1=#{digest(payload: payload, secret: secret, timestamp: timestamp)}"
    end

    def self.digest(payload:, secret:, timestamp:)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp.to_i}.#{payload}")
    end

    def self.verify(header_value:, payload:, secret:, tolerance: TOLERANCE, now: Time.current)
      parts = header_value.to_s.split(",").filter_map do |part|
        pair = part.split("=", 2)
        pair if pair.length == 2
      end.to_h
      timestamp = parts["t"].to_i
      signature = parts["v1"].to_s
      return false if timestamp.zero? || signature.empty?
      return false if (now.to_i - timestamp).abs > tolerance.to_i

      expected = digest(payload: payload, secret: secret, timestamp: Time.zone.at(timestamp))
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end
end
