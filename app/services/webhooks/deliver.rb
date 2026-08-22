require "net/http"

module Webhooks
  # Posts one delivery and decides what happens next. Failures are rescheduled
  # rather than raised so a dead customer endpoint does not fill the job
  # backend with retrying jobs.
  class Deliver
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    def self.call(...) = new(...).call

    def initialize(delivery:)
      @delivery = delivery
    end

    def call
      return delivery if delivery.status == "delivered"

      delivery.increment!(:attempts)
      body = delivery.payload.to_json

      response = post(body)

      if response.code.to_i.between?(200, 299)
        delivery.update!(status: "delivered", response_code: response.code.to_i, delivered_at: Time.current, last_error: nil)
      else
        reschedule(response_code: response.code.to_i, error: "endpoint responded #{response.code}")
      end

      delivery
    rescue StandardError => e
      reschedule(response_code: nil, error: "#{e.class}: #{e.message}")
      delivery
    end

    private

    attr_reader :delivery

    def post(body)
      uri = URI.parse(delivery.url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["User-Agent"] = "Meterly/1.0"
      request[Signature::HEADER] = Signature.header(payload: body, secret: delivery.secret)
      request.body = body

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    end

    def reschedule(response_code:, error:)
      if delivery.exhausted?
        delivery.update!(status: "failed", response_code: response_code, last_error: error)
      else
        delivery.update!(status: "pending", response_code: response_code, last_error: error,
                         deliver_after: delivery.next_backoff.from_now)
      end
    end
  end
end
