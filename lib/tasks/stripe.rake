namespace :stripe do
  desc "Publish an organization's active plans to Stripe as Products, Billing Meters and metered Prices"
  task :sync_catalogue, [ :organization_slug ] => :environment do |_task, args|
    organization = Organization.find_by!(slug: args.fetch(:organization_slug))
    gateway = Payments::StripeGateway.from_env

    organization.plans.active.find_each do |plan|
      result = gateway.sync_catalogue(plan)
      puts "#{plan.code}: product #{result.product_id}, #{result.prices.size} price(s)"
      result.skipped.each { |charge_id, reason| puts "  skipped charge #{charge_id}: #{reason}" }
    end
  end
end
