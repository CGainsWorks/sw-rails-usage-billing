# End to end check against a running Meterly.
#
#   bin/e2e                        # against http://localhost:3000
#   E2E_BASE_URL=... bin/e2e       # against anything else
#
# It provisions a throwaway organization, sends usage over the real HTTP API,
# closes the period through the real background worker, and then reads the
# invoice back over the API. Nothing is stubbed, so a pass means the whole
# pipeline works: ingest, idempotency, aggregation, tiered pricing, rounding,
# invoice numbering, payment collection and signed webhook delivery.
#
# It needs a web process and a job worker (bin/jobs) to be running.

require "net/http"
require "json"

BASE_URL = ENV.fetch("E2E_BASE_URL", "http://localhost:3000")
SLUG = "e2e-check".freeze
TIMEOUT = Integer(ENV.fetch("E2E_TIMEOUT_SECONDS", 90))

$failures = 0
$step = 0

def step(title)
  $step += 1
  puts "\n#{$step}. #{title}"
end

def check(label, actual, expected)
  if actual == expected
    puts "   ok    #{label}: #{actual}"
  else
    $failures += 1
    puts "   FAIL  #{label}: expected #{expected.inspect}, got #{actual.inspect}"
  end
  actual
end

def request(method, path, body: nil, token: nil)
  uri = URI.join(BASE_URL, path)
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method)
  http_request = klass.new(uri)
  http_request["Content-Type"] = "application/json"
  http_request["Authorization"] = "Bearer #{token}" if token
  http_request.body = body.to_json if body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", read_timeout: 20) do |http|
    http.request(http_request)
  end

  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  [ response.code.to_i, parsed ]
rescue JSON::ParserError
  [ response.code.to_i, { "raw" => response.body } ]
end

# bin/rails runner turns the ActiveRecord query cache on, which would make a
# polling loop read the same stale answer forever: the rows being waited for are
# written by the job worker, in another process.
def wait_until(description, seconds: TIMEOUT)
  deadline = Time.current + seconds
  while Time.current < deadline
    result = ActiveRecord::Base.uncached { yield }
    return result if result

    sleep 1
  end

  $failures += 1
  puts "   FAIL  timed out after #{seconds}s waiting for #{description}"
  nil
end

def teardown
  organization = Organization.find_by(slug: SLUG)
  return if organization.nil?

  ActiveRecord::Base.transaction do
    InvoiceLineItem.where(invoice_id: organization.invoices.select(:id)).delete_all
    PaymentAttempt.where(invoice_id: organization.invoices.select(:id)).delete_all
    organization.invoices.delete_all
    organization.usage_events.delete_all
    WebhookDelivery.where(webhook_endpoint_id: organization.webhook_endpoints.select(:id)).delete_all
    organization.webhook_endpoints.delete_all
    Charge.where(plan_id: organization.plans.select(:id)).delete_all
    organization.subscriptions.delete_all
    organization.customers.delete_all
    organization.plans.delete_all
    organization.billable_metrics.delete_all
    organization.api_keys.delete_all
    organization.users.delete_all
    organization.delete
  end
end

puts "Meterly end to end check against #{BASE_URL}"
teardown

step "Wait for the web process"
healthy = wait_until("the health endpoint", seconds: 60) { request(:get, "/up").first == 200 }
abort("the application at #{BASE_URL} never became healthy") unless healthy
puts "   ok    /up answered 200"

step "Provision a throwaway organization"
started_at = 45.days.ago.beginning_of_day
organization = Organization.create!(name: "End To End Ltd", slug: SLUG, currency: "GBP")
calls = organization.billable_metrics.create!(code: "e2e_calls", name: "Calls", aggregation_type: "count")
data = organization.billable_metrics.create!(code: "e2e_data", name: "Data", aggregation_type: "sum", property_name: "gigabytes")
plan = organization.plans.create!(code: "e2e_plan", name: "End to end", currency: "GBP", base_amount_cents: 10_000)
plan.charges.create!(billable_metric: calls, pricing_model: "tiered",
                     properties: { "tiers" => [ { "up_to" => 100, "unit_amount_cents" => 5 },
                                                { "up_to" => nil, "unit_amount_cents" => 2 } ] })
plan.charges.create!(billable_metric: data, pricing_model: "per_unit",
                     properties: { "unit_amount_cents" => 3, "free_units" => 10 })
organization.webhook_endpoints.create!(url: URI.join(BASE_URL, "/webhook-sink").to_s)
api_key = ApiKey.issue!(organization: organization, name: "End to end")
token = api_key.token
puts "   ok    organization #{organization.slug} with plan #{plan.code}"

step "Create a customer and a subscription over the API"
code, body = request(:post, "/api/v1/customers", token: token,
                     body: { customer: { external_id: "e2e_customer", name: "End To End Ltd", tax_rate_bps: 2_000 } })
check("create customer status", code, 201)

code, body = request(:post, "/api/v1/subscriptions", token: token,
                     body: { subscription: { external_id: "e2e_sub", external_customer_id: "e2e_customer",
                                             plan_code: "e2e_plan", started_at: started_at.utc.iso8601 } })
check("create subscription status", code, 201)
period_start = Time.zone.parse(body.dig("subscription", "current_period_start"))
closed_period_start = Subscription.find_by!(external_id: "e2e_sub").closed_billing_periods.first.starts_at
check("the first period has already closed", closed_period_start < period_start, true)

step "Send usage into the period that has closed"
inside_closed_period = closed_period_start + 2.days
events = 120.times.map do |index|
  { transaction_id: "e2e_call_#{index}", external_subscription_id: "e2e_sub", code: "e2e_calls",
    timestamp: (inside_closed_period + index.minutes).utc.iso8601 }
end
events += 5.times.map do |index|
  { transaction_id: "e2e_data_#{index}", external_subscription_id: "e2e_sub", code: "e2e_data",
    timestamp: (inside_closed_period + index.hours).utc.iso8601, properties: { gigabytes: "4.5" } }
end

code, body = request(:post, "/api/v1/events/batch", token: token, body: { events: events })
check("batch status", code, 200)
check("events accepted", body["accepted"], 125)
check("events rejected", body["rejected"], 0)

step "Replay one event to prove ingestion is idempotent"
replay = { event: events.first.merge(properties: { tampered: true }) }
code, body = request(:post, "/api/v1/events", token: token, body: replay)
check("replay status", code, 200)
check("replay outcome", body["status"], "duplicate")
check("stored event count", UsageEvent.where(organization_id: organization.id).count, 125)

step "Quote the period that is still running"
open_period_event = { event: { transaction_id: "e2e_open_1", external_subscription_id: "e2e_sub",
                               code: "e2e_calls", timestamp: 1.hour.ago.utc.iso8601 } }
request(:post, "/api/v1/events", token: token, body: open_period_event)

code, body = request(:get, "/api/v1/subscriptions/e2e_sub/current_usage", token: token)
check("current usage status", code, 200)
usage = body["current_usage"]
# The recurring fee plus one call in the opening tier, then 20 per cent VAT.
check("quoted subtotal", usage["subtotal_cents"], 10_005)
check("quoted total", usage["total_cents"], 12_006)

step "Close the period through the background worker"
Billing::CloseDueBillingPeriodsJob.perform_now
invoice = wait_until("the worker to write the invoice") do
  Invoice.find_by(subscription_id: Subscription.find_by!(external_id: "e2e_sub").id, period_start: closed_period_start)
end
abort("no invoice was produced") if invoice.nil?
puts "   ok    invoice #{invoice.number} written by the worker"

step "Read the invoice back over the API"
code, body = request(:get, "/api/v1/invoices/#{invoice.number}", token: token)
check("invoice status", code, 200)
invoice_json = body["invoice"]
# 100 calls at 5c plus 20 at 2c is 540c; 22.5GB less 10 free at 3c is 37.5c,
# which must round half up to 38c; the recurring fee is 10,000c.
check("invoice subtotal", invoice_json["subtotal_cents"], 10_578)
check("invoice VAT", invoice_json["tax_cents"], 2_116)
check("invoice total", invoice_json["total_cents"], 12_694)
check("invoice number format", invoice_json["number"], "INV-#{SLUG.upcase}-#{invoice.period_end.year}-00001")
check("line kinds", invoice_json["line_items"].map { |line| line["kind"] }, %w[subscription_fee usage usage])

tiers = invoice_json["line_items"].find { |line| line["metric_code"] == "e2e_calls" }.dig("breakdown", "tiers")
check("tier count on the calls line", tiers.length, 2)
check("first tier amount", tiers.first["amount_cents"], 500)

step "Confirm the invoice was collected"
paid = wait_until("the payment worker") do
  code, body = request(:get, "/api/v1/invoices/#{invoice.number}", token: token)
  body.dig("invoice", "status") == "paid" ? body["invoice"] : nil
end
check("payment recorded", paid && PaymentAttempt.where(invoice_id: invoice.id).succeeded.count, 1) if paid

step "Confirm the signed webhook arrived"
receipt = wait_until("the webhook sink") do
  _code, body = request(:get, "/webhook-sink", body: nil)
  Array(body["receipts"]).find do |candidate|
    candidate["event_type"] == "invoice.finalized" &&
      candidate.dig("payload", "data", "number") == invoice.number
  end
end
check("webhook signature verified", receipt && receipt["signature_valid"], true) if receipt

step "Tidy up"
teardown
WebhookSinkReceipt.where("payload -> 'data' ->> 'number' LIKE ?", "INV-#{SLUG.upcase}%").delete_all
puts "   ok    throwaway organization removed"

puts
if $failures.zero?
  puts "end to end check passed: #{$step} steps, no failures"
  exit 0
else
  puts "end to end check FAILED: #{$failures} failure(s)"
  exit 1
end
