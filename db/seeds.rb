# Demo data for the dashboard and for bin/e2e. Safe to run more than once.
#
# The suite builds what it needs with factories and db:prepare seeds whatever
# database it has just created, so seeding the test database would only put
# thousands of demo rows in the way.
return if Rails.env.test?

#
# It builds an organization that has been trading for a couple of months, so
# there is at least one closed billing period to invoice and one period still
# running for the usage preview to show.

ActiveRecord::Base.transaction do
  organization = Organization.find_or_create_by!(slug: "demo") do |org|
    org.name = "Northwind Cloud"
    org.currency = "GBP"
  end

  User.find_or_create_by!(email_address: "demo@meterly.test") do |user|
    user.organization = organization
    user.name = "Demo Operator"
    user.password = "password123"
    user.role = "admin"
  end

  # One metric per aggregation the engine supports.
  metrics = {
    api_requests: { name: "API requests", aggregation_type: "sum", property_name: "requests",
                    description: "Requests served, reported in batches" },
    data_processed_gb: { name: "Data processed", aggregation_type: "sum", property_name: "gigabytes",
                         description: "Gigabytes pushed through the pipeline" },
    active_seats: { name: "Active seats", aggregation_type: "max", property_name: "seats",
                    description: "Peak seats in use during the period" },
    unique_projects: { name: "Unique projects", aggregation_type: "unique_count", property_name: "project_id",
                       description: "Distinct projects that saw any activity" },
    alerts_sent: { name: "Alerts sent", aggregation_type: "count",
                   description: "One event per alert delivered" }
  }

  metrics.each do |code, attributes|
    metric = organization.billable_metrics.find_or_initialize_by(code: code.to_s)
    metric.assign_attributes(attributes)
    metric.save!
  end

  metric = ->(code) { organization.billable_metrics.find_by!(code: code) }

  starter = organization.plans.find_or_initialize_by(code: "starter")
  starter.assign_attributes(name: "Starter", description: "For teams getting started",
                            currency: "GBP", interval: "monthly", base_amount_cents: 4_900)
  starter.save!
  starter.charges.find_or_initialize_by(billable_metric: metric.call("api_requests")).update!(
    pricing_model: "package",
    properties: { "package_size" => 10_000, "package_amount_cents" => 90, "free_units" => 50_000 }
  )
  starter.charges.find_or_initialize_by(billable_metric: metric.call("data_processed_gb")).update!(
    pricing_model: "per_unit", properties: { "unit_amount_cents" => 15, "free_units" => 20 }
  )

  growth = organization.plans.find_or_initialize_by(code: "growth")
  growth.assign_attributes(name: "Growth", description: "Graduated request pricing and seat billing",
                           currency: "GBP", interval: "monthly", base_amount_cents: 24_900,
                           minimum_amount_cents: 40_000)
  growth.save!
  growth.charges.find_or_initialize_by(billable_metric: metric.call("api_requests")).update!(
    pricing_model: "tiered",
    properties: { "free_units" => 100_000, "tiers" => [
      { "up_to" => 1_000_000, "unit_amount_cents" => "0.05" },
      { "up_to" => 5_000_000, "unit_amount_cents" => "0.03" },
      { "up_to" => nil, "unit_amount_cents" => "0.02" }
    ] }
  )
  growth.charges.find_or_initialize_by(billable_metric: metric.call("data_processed_gb")).update!(
    pricing_model: "volume",
    properties: { "tiers" => [
      { "up_to" => 1_000, "unit_amount_cents" => 12 },
      { "up_to" => 10_000, "unit_amount_cents" => 9 },
      { "up_to" => nil, "unit_amount_cents" => 6 }
    ] }
  )
  growth.charges.find_or_initialize_by(billable_metric: metric.call("active_seats")).update!(
    pricing_model: "per_unit", properties: { "unit_amount_cents" => 800 }
  )

  scale = organization.plans.find_or_initialize_by(code: "scale")
  scale.assign_attributes(name: "Scale", description: "Committed spend with the cheapest rates",
                          currency: "GBP", interval: "monthly", base_amount_cents: 99_900,
                          minimum_amount_cents: 150_000)
  scale.save!
  scale.charges.find_or_initialize_by(billable_metric: metric.call("api_requests")).update!(
    pricing_model: "tiered",
    properties: { "free_units" => 1_000_000, "tiers" => [
      { "up_to" => 10_000_000, "unit_amount_cents" => "0.02" },
      { "up_to" => nil, "unit_amount_cents" => "0.012" }
    ] }
  )
  scale.charges.find_or_initialize_by(billable_metric: metric.call("unique_projects")).update!(
    pricing_model: "per_unit", properties: { "unit_amount_cents" => 250, "free_units" => 25 }
  )
  scale.charges.find_or_initialize_by(billable_metric: metric.call("alerts_sent")).update!(
    pricing_model: "per_unit", properties: { "unit_amount_cents" => 2, "free_units" => 100 }
  )

  customers = [
    { external_id: "cus_bramble", name: "Bramble Analytics", email: "ap@bramble.test", tax_rate_bps: 2_000, plan: growth },
    { external_id: "cus_kestrel", name: "Kestrel Health", email: "finance@kestrel.test", tax_rate_bps: 2_000, plan: scale },
    { external_id: "cus_tinbox", name: "Tinbox Studio", email: "hello@tinbox.test", tax_rate_bps: 0, plan: starter },
    { external_id: "decline_riverbank", name: "Riverbank Media", email: "ap@riverbank.test", tax_rate_bps: 2_000, plan: growth }
  ]

  started_at = 45.days.ago.beginning_of_day

  customers.each do |attributes|
    plan = attributes.delete(:plan)
    customer = organization.customers.find_or_initialize_by(external_id: attributes[:external_id])
    customer.assign_attributes(attributes.merge(currency: "GBP"))
    customer.save!

    subscription = organization.subscriptions.find_or_initialize_by(external_id: "sub_#{customer.external_id}")
    subscription.assign_attributes(customer: customer, plan: plan, started_at: started_at)
    subscription.save!
  end

  organization.webhook_endpoints.find_or_create_by!(url: ENV.fetch("WEBHOOK_SINK_URL", "http://localhost:3000/webhook-sink"))

  ApiKey.issue!(organization: organization, name: "Demo ingest key") if organization.api_keys.none?
end

# Usage events, written straight to the database: a realistic month of traffic
# inserted one row at a time would make seeding unbearable.
organization = Organization.find_by!(slug: "demo")

# Each customer sends a different shape of traffic, which is what makes the
# invoices worth looking at.
PROFILES = {
  "cus_bramble" => { batches_per_day: 24, requests_per_batch: 900..2_400, gigabytes: 30.0..90.0, seats: 18..34, projects: 3..8, alerts: 2..9 },
  "cus_kestrel" => { batches_per_day: 24, requests_per_batch: 4_000..9_000, gigabytes: 120.0..320.0, seats: 40..80, projects: 6..14, alerts: 5..18 },
  "cus_tinbox" => { batches_per_day: 8, requests_per_batch: 150..600, gigabytes: 4.0..22.0, seats: 3..9, projects: 1..4, alerts: 0..3 },
  "decline_riverbank" => { batches_per_day: 18, requests_per_batch: 700..1_900, gigabytes: 20.0..70.0, seats: 12..25, projects: 2..6, alerts: 1..6 }
}.freeze

if organization.usage_events.none?
  now = Time.current
  rows = []
  random = Random.new(20_260_101)
  regions = %w[eu-west-1 us-east-1]

  organization.subscriptions.includes(:customer, plan: { charges: :billable_metric }).find_each do |subscription|
    codes = subscription.plan.charges.map { |charge| charge.billable_metric.code }
    profile = PROFILES.fetch(subscription.customer.external_id)
    days = ((now - subscription.started_at) / 1.day).floor

    event = lambda do |code, occurred_at, suffix, properties|
      rows << { organization_id: organization.id, subscription_id: subscription.id,
                transaction_id: "seed_#{code}_#{subscription.id}_#{suffix}", code: code,
                occurred_at: occurred_at, properties: properties, created_at: now }
    end

    days.times do |day|
      midnight = subscription.started_at + day.days

      if codes.include?("api_requests")
        profile[:batches_per_day].times do |batch|
          event.call("api_requests", midnight + batch.hours + random.rand(0..59).minutes, "#{day}_#{batch}",
                     { "requests" => random.rand(profile[:requests_per_batch]).to_s,
                       "region" => regions[random.rand(regions.length)] })
        end
      end

      if codes.include?("data_processed_gb")
        event.call("data_processed_gb", midnight + 3.hours, day.to_s,
                   { "gigabytes" => random.rand(profile[:gigabytes]).round(2).to_s })
      end

      if codes.include?("active_seats")
        event.call("active_seats", midnight + 12.hours, day.to_s, { "seats" => random.rand(profile[:seats]).to_s })
      end

      if codes.include?("unique_projects")
        random.rand(profile[:projects]).times do |index|
          event.call("unique_projects", midnight + index.hours, "#{day}_#{index}",
                     { "project_id" => "proj_#{random.rand(1..40)}" })
        end
      end

      next unless codes.include?("alerts_sent")

      random.rand(profile[:alerts]).times do |index|
        event.call("alerts_sent", midnight + index.hours + 30.minutes, "#{day}_#{index}",
                   { "severity" => %w[warning critical][random.rand(2)] })
      end
    end
  end

  rows.each_slice(5_000) { |slice| UsageEvent.insert_all!(slice) }
  puts "seeded #{rows.length} usage events"
end

# Close every period that has already finished and then take the money, so the
# dashboard has finished invoices to show. In production the nightly job does
# both steps instead. The demo history is always collected by the simulated
# gateway, whatever PAYMENT_PROVIDER says, so its declined customers stay
# declined.
demo_gateway = Payments::SimulatedGateway.new
organization.subscriptions.find_each do |subscription|
  subscription.closed_billing_periods.each do |period|
    invoice = Billing::GenerateInvoice.call(subscription: subscription, period: period)
    Billing::FinalizeInvoice.call(invoice: invoice)
    Payments::Collect.call(invoice: invoice.reload, gateway: demo_gateway)
  end
end

puts "organization #{organization.slug}: #{organization.invoices.count} invoices, sign in as demo@meterly.test / password123"
