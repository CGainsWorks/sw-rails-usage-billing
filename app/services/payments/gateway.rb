module Payments
  # Collection is behind an adapter so the billing engine never knows which
  # provider took the money.
  #
  # LIMITATION: this repository ships only the simulated gateway. Wiring a real
  # provider needs a merchant account, live API credentials and a publicly
  # reachable callback URL, none of which belong in a portfolio project, so
  # StripeGateway is a documented stub. See docs/limitations.md.
  module Gateway
    Result = Data.define(:success, :reference, :failure_reason) do
      def success? = success
    end

    def self.current
      case ENV.fetch("PAYMENT_PROVIDER", "simulated")
      when "simulated" then SimulatedGateway.new
      when "stripe" then StripeGateway.new
      else raise ArgumentError, "unknown payment provider #{ENV['PAYMENT_PROVIDER'].inspect}"
      end
    end
  end
end
