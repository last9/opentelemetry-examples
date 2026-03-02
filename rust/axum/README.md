# Instrumenting Axum with OpenTelemetry (Rust 1.74)

Demonstrates OpenTelemetry tracing for an [Axum](https://github.com/tokio-rs/axum) HTTP service on **Rust 1.74** using `opentelemetry` 0.27 — the highest otel version compatible with Rust 1.74 (otel 0.28+ requires Rust 1.75).

## Why these versions?

| Package | Version | MSRV | Reason |
|---|---|---|---|
| `opentelemetry` | 0.27 | 1.70 | Newest compatible with Rust 1.74 |
| `axum` | 0.6 | ~1.60 | axum 0.7+ requires Rust 1.75 |
| `tower-http` | 0.4 | ~1.60 | Matches axum 0.6 |
| `tracing-opentelemetry` | 0.28 | 1.70 | Bridges `tracing` spans → OTel |

## How it works

```
HTTP Request
    → axum + tower-http TraceLayer   (creates tracing spans)
        → tracing-opentelemetry      (bridges to OTel spans)
            → opentelemetry-otlp     (exports to Last9)
```

`#[instrument]` on handler functions creates child spans automatically — no custom middleware or proc macros needed.

## Features demonstrated

### External HTTP calls with W3C trace context propagation

Outgoing `reqwest` calls carry a `traceparent` header so the downstream service
can join the same distributed trace:

```rust
struct HeaderMapInjector<'a>(&'a mut reqwest::header::HeaderMap);

impl opentelemetry::propagation::Injector for HeaderMapInjector<'_> {
    fn set(&mut self, key: &str, value: String) { /* insert header */ }
}

// Before sending the request:
inject_trace_context(&mut headers);  // adds traceparent + tracestate
```

### SQLite database calls with traced spans

`rusqlite` is a synchronous C binding. Wrapping it in `spawn_blocking` keeps
the Tokio executor unblocked, and `#[instrument]` adds an OTel child span:

```rust
#[instrument(skip(db))]
async fn fetch_users_from_db(db: Db) -> Vec<User> {
    tokio::task::spawn_blocking(move || {
        // synchronous SQLite query here
    }).await.unwrap_or_default()
}
```

### Log-trace correlation

Every log line can carry the current OTel `trace_id`, enabling you to jump
from a log entry directly to its trace in Last9 APM:

```rust
info!(trace_id = %telemetry::current_trace_id(), count = users.len(), "Returning users");
```

Logs are emitted as JSON (via `tracing-subscriber` json feature) so the
`trace_id` field is machine-parseable.

## Prerequisites

- Rust 1.74 (enforced by `rust-toolchain.toml`)
- [Last9](https://app.last9.io) account

## Quick Start

1. Copy and fill in credentials:

```bash
cp .env.example .env
```

Edit `.env` with your Last9 credentials from the dashboard under **Integrations → OpenTelemetry**.

2. Source the env and run:

```bash
source .env
cargo run
```

3. Make requests:

```bash
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/users
curl http://localhost:8080/users/1
curl http://localhost:8080/external
```

4. View traces in [Last9 APM → Traces](https://app.last9.io), filtered by `rust-axum-service`.

## Configuration

| Variable | Description | Default |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint | `https://otlp.last9.io` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers (comma-separated `key=value`) | — |
| `OTEL_SERVICE_NAME` | Service name in traces | `rust-axum-service` |
| `OTEL_SERVICE_VERSION` | Service version | `1.0.0` |
| `DEPLOYMENT_ENVIRONMENT` | Environment tag | `production` |
| `RUST_LOG` | Log filter | `info` |

## Endpoints

| Endpoint | Description |
|---|---|
| `GET /` | Root — simple response |
| `GET /health` | Health check |
| `GET /users` | List users (SQLite query, traced with `#[instrument]`) |
| `GET /users/:id` | Get user by ID (SQLite lookup) |
| `GET /external` | Outgoing HTTP call with W3C trace context propagation |

## Project Structure

```
rust/axum/
├── src/
│   ├── main.rs        # Axum server, routes, handlers, W3C propagation
│   └── telemetry.rs   # OTel SDK init, log-trace correlation helper
├── Cargo.toml         # Pinned dependencies for Rust 1.74
├── rust-toolchain.toml
├── .env.example
└── .gitignore
```

## Dependency pinning for Rust 1.74

Three layers of pins are required to avoid transitive deps that need Rust 1.83+:

| Pin | Reason |
|---|---|
| `url = "=2.5.0"`, `idna = "=0.5.0"` | `idna 1.x` → `icu_properties_data` requires Rust 1.83 |
| `opentelemetry-otlp` with `default-features = false` | `grpc-tonic` default pulls in tonic/hyper 1.x |
| `reqwest` with `rustls-tls-webpki-roots` (not `rustls-tls`) | `rustls-native-certs` → `security-framework 3.x` (2024 edition, needs Rust 1.83 on macOS) |
