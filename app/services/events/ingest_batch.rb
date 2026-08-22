module Events
  # A batch is deliberately not one transaction: one malformed event in a
  # thousand should not reject the other 999, so each is reported on its own.
  class IngestBatch
    MAX_EVENTS = 500

    Summary = Data.define(:results, :accepted, :duplicates, :rejected) do
      def to_h = { accepted: accepted, duplicates: duplicates, rejected: rejected }
    end

    def self.call(...) = new(...).call

    def initialize(organization:, events:)
      @organization = organization
      @events = Array(events)
    end

    def call
      results = events.map { |attributes| Ingest.call(organization: organization, attributes: attributes) }

      Summary.new(
        results: results,
        accepted: results.count { |result| result.status == "accepted" },
        duplicates: results.count { |result| result.status == "duplicate" },
        rejected: results.count { |result| result.status == "rejected" }
      )
    end

    private

    attr_reader :organization, :events
  end
end
