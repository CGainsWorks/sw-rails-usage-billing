# Status

Last updated 2026-10-16.

Meterly is a usage-based billing engine on Rails 8.1 and PostgreSQL 16. There
is no hardware in this project. The one paid service it can talk to, Stripe, is
emulated with stripe-mock in CI and has never been called for real.

## Complete

- Metering: idempotent ingest on `(organization_id, transaction_id)`, a batch
  endpoint of up to 500 events, per-key rate limiting, count, sum, max and
  unique count aggregations in PostgreSQL, property filters.
- Pricing: per unit, package, graduated and volume charges with free
  allowances, a recurring fee and a minimum commitment, rounded once per line.
- Invoicing: anchored periods, proration on termination, flat VAT per
  customer, gapless invoice numbers under an advisory lock, a nightly close on
  Solid Queue.
- Outbound webhooks signed with HMAC-SHA256 and retried with backoff.
- Simulated collection (`Payments::SimulatedGateway`), deterministic and the
  default.
- Stripe collection (`Payments::StripeGateway`) on the official `stripe` gem
  20.0.0: customers, a Product per plan, a Billing Meter per metric, a metered
  Price per charge, meter events, invoices mirrored line for line then
  finalised and paid, idempotency keys on every write, retries with backoff on
  outages. Provider ids live in a separate `provider_references` table.
- Inbound Stripe webhooks at `POST /webhooks/stripe`, verified with
  `Stripe::Webhook.construct_event`, applying `invoice.paid` and
  `invoice.payment_failed` at most once.
- CI on every push in one job: bundler frozen to `Gemfile.lock`, RuboCop with
  `rubocop-rails-omakase`, Brakeman, bundler-audit, importmap audit, RSpec
  against PostgreSQL and stripe-mock service containers, then the end to end
  check with the worker collecting through the Stripe gateway. The production
  image is built and booted whenever the Dockerfile, gems or Ruby version
  change, on pushes and pull requests.
- Tests: 188 RSpec examples, 0 failures, with stripe-mock running. Without
  `STRIPE_MOCK_URL` the 11 stripe-mock examples are skipped locally and fail
  the build in CI.
- README section on how sibling services would send metered usage, with an
  LLM token-count example.

## In progress

- Nothing.

## Not started

- A run against a Stripe account in test mode, with the Stripe CLI forwarding
  webhooks.
- A dunning schedule that retries a declined invoice on a timetable.
- PDF invoices and an `InvoiceMailer`.
- A load test of the ingest API. No throughput figure has been measured.
- An API for the catalogue (metrics, plans, charges). Today they are created in
  a seed or the console.
- Wiring the sibling repositories to send usage. The README shows how; none of
  them does yet.

## Limitations

- **Stripe is emulated, not used.** CI drives the gateway through the official
  client against `stripe/stripe-mock:v0.206.0`, which validates every request
  against Stripe's API specification. It is stateless, answers with fixture
  objects, never declines and never sends webhooks, so declines and outages
  are tested by raising the gem's own errors at the client and the webhook
  receiver by signing events in the test with a secret generated for the run.
  Nothing has been sent to Stripe itself.
- Stripe meters only count or sum and cannot filter on properties, so `max`,
  `unique_count` and filtered metrics are not published to Stripe. Package and
  volume prices with a free allowance are skipped for the same reason.
- Tax is one flat rate per customer.
- One database, one region. See [docs/limitations.md](docs/limitations.md).
