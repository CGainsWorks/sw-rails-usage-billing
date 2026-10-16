module Payments
  # Collection is behind an adapter so the billing engine never knows which
  # provider took the money. Meterly rates the usage and writes the invoice;
  # the gateway only collects it.
  #
  # Two adapters exist:
  #
  # * SimulatedGateway, the default, is deterministic and offline. Development,
  #   the demo seed and most of the test suite use it.
  # * StripeGateway talks to Stripe through the official stripe gem. CI runs it
  #   against stripe-mock. Running it against a real Stripe account (test mode or
  #   live) needs keys that are not in this repository. See the README.
  module Gateway
    Result = Data.define(:success, :reference, :failure_reason) do
      def success? = success
    end

    # Raised for failures worth retrying: the provider was unreachable, rate
    # limited or had an internal error. The jobs retry on it with backoff.
    TransientError = Class.new(StandardError)

    def self.provider_name = ENV.fetch("PAYMENT_PROVIDER", "simulated")

    def self.current
      case provider_name
      when "simulated" then SimulatedGateway.new
      when "stripe" then StripeGateway.from_env
      else raise ArgumentError, "unknown payment provider #{ENV['PAYMENT_PROVIDER'].inspect}"
      end
    end

    # Whether accepted usage events are also copied to the provider's own
    # meters. Off unless asked for, because Meterly is the system of record for
    # usage either way.
    def self.mirror_usage?
      provider_name == "stripe" && ENV["STRIPE_MIRROR_USAGE"] == "true"
    end
  end
end
