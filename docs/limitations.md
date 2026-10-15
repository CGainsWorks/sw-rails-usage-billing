# Limitations and what would come next

Meterly is a working billing engine, built and verified on a single developer
machine. The boundaries below are deliberate and each one is marked in the code
where it bites.

## No live payment provider

`Payments::SimulatedGateway` is the only gateway that is implemented. Charging a
real card needs a merchant account, live API credentials and a publicly
reachable callback URL, none of which belong in a portfolio repository, so
collection is simulated:

* Every charge succeeds, except for customers whose `external_id` starts with
  `decline_`, which always fail with `card_declined`. That is how the seed data
  and the specs exercise the failed-payment path deterministically.
* `Payments::StripeGateway` is a stub that raises `NotImplementedError`. It
  carries the shape of the real implementation in a comment, including the
  idempotency key that stops a retried job charging a card twice.

Swapping in a real provider means writing that one class. Nothing else in the
billing engine knows which provider took the money.

**Next:** implement the Stripe adapter, add a dunning schedule that retries a
declined invoice on a timetable rather than once and record partial payments.

## No email

Nothing is sent to a customer. Invoices are announced over webhooks and Action
Mailer is configured but unused. A real deployment would email the invoice PDF
to the billing contact.

**Next:** an `InvoiceMailer` with a PDF attachment and a bounce-handling path.

## No PDF rendering

Invoices render as HTML and JSON. Accounts departments want a PDF.

## Tax is a flat rate per customer

`customer.tax_rate_bps` is a single rate applied to the whole subtotal. Real VAT
handling needs place-of-supply rules, reverse charge for business customers in
other countries, per-line rates for mixed goods and services and a validated VAT
number. That is a domain of its own and it is not modelled here.

## Credits, discounts and currency conversion are not modelled

There are no coupons, no prepaid credit balances that usage draws down and no
multi-currency wallets. A subscription bills in its plan currency and that is
the currency of the invoice.

## Deployment is not automated

The repository ships a production `Dockerfile` that CI builds on every push but
there is no deployment pipeline and no infrastructure code. Kamal was
deliberately left out of the generated app. Running it in production needs:

* `SECRET_KEY_BASE` in the environment. The generated Rails credentials files
  were removed so a clone has nothing encrypted it cannot open.
* `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD` and `DB_NAME`, or a `DATABASE_URL`.
* At least one `bin/jobs` worker beside the web process, because the nightly
  billing run, payment collection and webhook delivery all happen there.

## The webhook sink is a test affordance

`/webhook-sink` lets the application receive its own webhooks so `bin/e2e` can
prove the delivery path over real HTTP, signature and all. The route is not
mounted in production and the receipts table it writes to is only used by the
demo and the end to end check.

## Scale has not been measured

The aggregation queries are indexed on `(subscription_id, code, occurred_at)`
and run in PostgreSQL rather than in Ruby, which is the shape that matters but
no load test has been run. At high volume the next steps would be:

* Partition `usage_events` by month and detach old partitions to cold storage.
* Materialise daily per-metric rollups so a period aggregation reads 31 rows
  instead of millions, keeping raw events only for audit and disputes.
* Move ingest behind a queue so a slow database cannot reject a customer's
  events.

## Single region, single database

Everything is one PostgreSQL database, including the job queue and the cache.
That is the right trade at this size and it is a genuine constraint: there is no
read replica, no sharding by tenant and no cross-region failover.
