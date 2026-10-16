# API reference

Base path `/api/v1`. Everything speaks JSON.

## Authentication

Every request carries an API key as a bearer token. Keys are created in the
dashboard under Settings and are shown once, because only a SHA-256 digest is
stored.

```
Authorization: Bearer mtr_sk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

A missing, unknown or revoked key gets a 401:

```json
{ "error": { "code": "unauthorized", "message": "a valid API key is required", "details": [] } }
```

Traffic is rate limited to 600 requests a minute per key, answered with a 429
and `{"error": {"code": "rate_limited"}}`.

## Events

### POST /api/v1/events

```json
{
  "event": {
    "transaction_id": "req-2026-08-22-0001",
    "external_subscription_id": "sub_cus_bramble",
    "code": "api_requests",
    "timestamp": "2026-08-22T09:15:00Z",
    "properties": { "requests": "1200", "region": "eu-west-1" }
  }
}
```

* `transaction_id` is the idempotency key and is unique per organization.
* `timestamp` accepts ISO 8601 or epoch seconds and defaults to now. It must
  fall inside the subscription's lifetime and cannot be more than five minutes
  in the future.
* `code` must match a billable metric that exists, which catches an integration
  sending events nobody is priced for.

`201` on the first send, `200` with `{"status": "duplicate"}` on a replay,
`422` with a list of reasons if it is rejected.

### POST /api/v1/events/batch

Up to 500 events in `{"events": [...]}`. The batch is not one transaction: each
event is reported on separately so one malformed row cannot reject the other 499.

```json
{
  "accepted": 124,
  "duplicates": 1,
  "rejected": 0,
  "results": [ { "index": 0, "status": "accepted", "errors": [], "transaction_id": "..." } ]
}
```

### GET /api/v1/events

Recent events, newest first. Optional `code` and `limit` (max 200).

## Customers

### POST /api/v1/customers

Upsert by `external_id`, so a retried create returns 200 rather than a conflict.

```json
{ "customer": { "external_id": "cus_bramble", "name": "Bramble Analytics",
                "email": "ap@bramble.test", "tax_rate_bps": 2000 } }
```

`tax_rate_bps` is basis points, so 2000 is 20 per cent VAT.

### GET /api/v1/customers, GET /api/v1/customers/:external_id

## Subscriptions

### POST /api/v1/subscriptions

```json
{ "subscription": { "external_id": "sub_cus_bramble", "external_customer_id": "cus_bramble",
                    "plan_code": "growth", "started_at": "2026-07-08T00:00:00Z" } }
```

`started_at` is the billing anchor. Every future period boundary is derived from
it.

### GET /api/v1/subscriptions/:external_id/current_usage

What the open period would cost if it were closed now, in the same shape as an
invoice.

```json
{
  "current_usage": {
    "period_start": "2026-08-07T00:00:00Z",
    "period_end": "2026-09-07T00:00:00Z",
    "currency": "GBP",
    "subtotal_cents": 122568,
    "tax_rate_bps": 2000,
    "tax_cents": 24514,
    "total_cents": 147082,
    "lines": [
      { "kind": "subscription_fee", "description": "Growth subscription", "amount_cents": 24900 },
      { "kind": "usage", "description": "API requests", "metric_code": "api_requests",
        "quantity": "1218740.0", "amount_cents": 53562,
        "breakdown": { "model": "tiered", "tiers": [ { "from": "0", "up_to": "1000000.0", "units": "1000000.0",
                                                       "unit_amount_cents": "0.05", "amount_cents": 50000 } ] } }
    ]
  }
}
```

### POST /api/v1/subscriptions/:external_id/terminate

Ends the subscription now. The part period that was served is invoiced by the
next billing run with the recurring fee prorated. Calling it twice is safe.

## Invoices

### GET /api/v1/invoices

Optional `status` (`draft`, `finalized`, `paid`, `void`), `external_customer_id`
and `limit`.

### GET /api/v1/invoices/:number

Accepts an invoice number such as `INV-DEMO-2026-00001` or the numeric id.
Returns the invoice with `line_items`, each carrying the breakdown it was priced
with.

## Plans

### GET /api/v1/plans, GET /api/v1/plans/:code

The catalogue, including every charge with its pricing model and properties.

## Webhooks

Endpoints are added in the dashboard. Each delivery is a POST with:

```
Content-Type: application/json
X-Meterly-Signature: t=1755859200,v1=9f86d0818...
```

The signature is `HMAC-SHA256(secret, "#{timestamp}.#{body}")`. Verify by
recomputing it and rejecting anything more than five minutes old, which stops a
captured request being replayed later.

```ruby
Webhooks::Signature.verify(header_value: request.headers["X-Meterly-Signature"],
                           payload: request.raw_post, secret: endpoint_secret)
```

| Event | Sent when |
|---|---|
| `invoice.finalized` | An invoice is numbered and issued |
| `invoice.paid` | Collection succeeded |
| `invoice.payment_failed` | Collection was declined |

The body is `{"id": "...", "type": "...", "created_at": "...", "data": {invoice}}`.
Failed deliveries are retried after 30s, 1m, 2m, 4m and 8m before being marked
failed.

## Inbound Stripe webhooks

### POST /webhooks/stripe

Not under `/api/v1` and not authenticated by API key: Stripe signs each
delivery instead. The `Stripe-Signature` header is checked with the official
gem (`Stripe::Webhook.construct_event`) against `STRIPE_WEBHOOK_SECRET` before
the body is parsed, with Stripe's default tolerance of five minutes.

| Answer | When |
|---|---|
| `200` with `{"received": true, "outcome": "..."}` | The signature is valid. The outcome is `marked_paid`, `already_paid`, `recorded_failure`, `duplicate`, `not_finalized`, `unknown_invoice` or `ignored` |
| `400` | The signature is missing, wrong, from another secret or too old, or the body is not JSON |
| `503` | `STRIPE_WEBHOOK_SECRET` is not configured |

| Stripe event | Effect |
|---|---|
| `invoice.paid` | The matching Meterly invoice is marked paid and `invoice.paid` is published, once |
| `invoice.payment_failed` | A failed payment attempt is recorded once per Stripe event id and `invoice.payment_failed` is published |

Every other event type is acknowledged and ignored.
