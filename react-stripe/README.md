# React + Stripe.js — OpenTelemetry Instrumentation

Observability for a Stripe checkout flow: **traces and logs** from the React
frontend (Stripe.js, payment confirmation, 3DS challenges) through to the Rails
API backend (PaymentIntent creation, webhook processing).

## Why This Matters

Stripe's dashboard shows you *what* happened (payment succeeded, card declined).
It doesn't show you *how the user experienced it* — how long the PaymentElement
took to render, whether a 3DS redirect silently failed, or if your backend
webhook handler is adding 200ms of latency before Stripe marks the payment
complete.

This example instruments the gaps that payment providers and generic APM tools miss:

| Gap | What you get |
|---|---|
| **Stripe.js load time** | `stripe.js.load` span — see if the SDK download is slow in specific regions |
| **PaymentElement render latency** | `stripe.elements.mount` — time from React render to card input ready |
| **3DS challenge lifecycle** | `stripe.3ds.challenge` span — the user left your page for bank auth. Did they come back? How long did it take? |
| **Payment confirmation round-trip** | `stripe.payment.confirm` — end-to-end from button click to Stripe response, including decline codes as span attributes |
| **Frontend-to-backend correlation** | Browser traces link to backend `stripe.payment_intent.create` and `stripe.webhook.process` spans via W3C trace context |
| **Structured payment logs** | Every payment event (`payment.started`, `payment.succeeded`, `payment.failed`, `3ds.required`, `dispute.created`) emits an OTel log record with payment attributes — queryable, alertable, no grep required |

**vs. Datadog / New Relic**: Vendor agents auto-instrument HTTP and database calls
but have zero Stripe.js-specific instrumentation. You won't see PaymentElement
mount time, 3DS redirect outcomes, or decline codes as first-class trace
attributes. This example gives you that coverage using open-source OpenTelemetry —
portable to any OTel-compatible backend.

## What Gets Instrumented

| Signal | Where | Span / log name |
|---|---|---|
| Stripe.js script load | Frontend | `stripe.js.load` |
| PaymentElement mount time | Frontend | `stripe.elements.mount` |
| Payment confirmation | Frontend | `stripe.payment.confirm` |
| 3DS redirect + return | Frontend | `stripe.3ds.challenge` |
| Payment errors | Frontend | log `payment.failed` |
| PaymentIntent creation | Backend | `stripe.payment_intent.create` |
| Webhook processing | Backend | `stripe.webhook.process` |
| Disputes | Backend | `stripe.webhook.process` + error status |

## Prerequisites

- Node.js 18+
- Ruby 3.3.3 + Bundler
- A [Stripe test account](https://dashboard.stripe.com/register) (free)
- A [Last9 account](https://app.last9.io) for receiving telemetry

## Quick Start

### 1. Backend

```bash
cd backend
cp .env.example .env
# Edit .env — add STRIPE_SECRET_KEY, OTEL_* values

bundle install
rails server -p 3001
```

### 2. Frontend

```bash
cd frontend
cp .env.example .env
# Edit .env — add REACT_APP_STRIPE_PUBLISHABLE_KEY, REACT_APP_OTEL_* values

npm install
npm start
```

Open http://localhost:3000. Use a [Stripe test card](https://docs.stripe.com/testing#cards):

| Scenario | Card number |
|---|---|
| Success | `4242 4242 4242 4242` |
| Card declined | `4000 0000 0000 0002` |
| Insufficient funds | `4000 0000 0000 9995` |
| 3DS required | `4000 0025 0000 3155` |

Use any future expiry date, any 3-digit CVC, any postal code.

### 3. Webhooks (optional)

To test webhook instrumentation locally, install the [Stripe CLI](https://docs.stripe.com/stripe-cli) and forward events:

```bash
stripe listen --forward-to localhost:3001/api/v1/webhooks
```

Copy the webhook signing secret printed by the CLI and set it as
`STRIPE_WEBHOOK_SECRET` in `backend/.env`.

## Configuration

### Frontend (`frontend/.env`)

| Variable | Description |
|---|---|
| `REACT_APP_STRIPE_PUBLISHABLE_KEY` | Stripe test publishable key (`pk_test_...`) |
| `REACT_APP_BACKEND_URL` | Rails API URL (default: `http://localhost:3001`) |
| `REACT_APP_OTEL_TRACES_ENDPOINT` | Last9 client monitoring traces endpoint |
| `REACT_APP_OTEL_LOGS_ENDPOINT` | Last9 client monitoring logs endpoint |
| `REACT_APP_OTEL_API_TOKEN` | Last9 **client** token (origin-restricted) |
| `REACT_APP_OTEL_ORIGIN` | Allowed origin set on the client token |
| `REACT_APP_OTEL_SERVICE_NAME` | Service name shown in Last9 |

### Backend (`backend/.env`)

| Variable | Description |
|---|---|
| `STRIPE_SECRET_KEY` | Stripe test secret key (`sk_test_...`) |
| `STRIPE_WEBHOOK_SECRET` | Webhook signing secret (`whsec_...`) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS` | Last9 auth header (`Authorization=Basic ...`) |
| `OTEL_SERVICE_NAME` | Service name shown in Last9 |

## Docker

```bash
cp backend/.env.example backend/.env  # edit values
cp frontend/.env.example frontend/.env  # edit values
docker compose up
```

## Verification

After a test payment:

1. **Last9 Traces** — search for service `stripe-checkout`. You should see:
   - `stripe.js.load` → `GET /api/v1/payment_intents` → `stripe.payment.confirm`
2. **Last9 Logs** — filter by `service.name = stripe-checkout`. You should see
   `payment.started`, `payment.succeeded` (or `payment.failed`) log records.
3. **Backend traces** — service `stripe-payments-api`, span `stripe.payment_intent.create`
   with `payment.amount`, `payment.currency`, `payment.intent_id` attributes.
