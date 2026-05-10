# GORM with the official OpenTelemetry plugin + last9/go-agent SDK

End-to-end example for [GORM v2](https://gorm.io) instrumented with
[`gorm.io/plugin/opentelemetry`](https://github.com/go-gorm/opentelemetry)
(the official tracing plugin maintained by the GORM team) layered on top of
[`last9/go-agent`](https://github.com/last9/go-agent)'s
[`integrations/database`](https://github.com/last9/go-agent#database-support)
SQL wrapper. Every HTTP request produces a two-layer trace:

```
gin handler span
  └─ select users / insert users / ...  (gorm.io/plugin/opentelemetry)
        └─ postgres.query                (integrations/database / otelsql)
```

`last9/go-agent` does not ship a GORM wrapper. The upstream plugin is current
on OpenTelemetry semconv, ships connection-pool metrics by default, and is
maintained alongside GORM itself — wrapping it would only duplicate work. See
the [go-agent README](https://github.com/last9/go-agent#orm-support-gorm) for
the full rationale.

## What this example demonstrates

- Wiring the upstream `gorm.io/plugin/opentelemetry/tracing` plugin
- Two-layer trace: `database.Open` (otelsql) → GORM postgres dialector via
  `postgres.Config{Conn: sqlDB}`
- OTel semconv v1.30.0 attributes emitted by the upstream plugin
  (`db.system.name`, `db.query.text`, `db.operation.name`,
  `db.collection.name`, `db.query.summary`, `db.rows_affected`,
  `server.address`)
- Connection-pool gauges (`go.sql.connections_*`) emitted by the upstream
  plugin
- A `/users/slow` endpoint running `pg_sleep(0.5)` to surface a long
  span by duration alone (no separate "slow=true" attribute — Last9 derives
  slow queries from span duration server-side)

## Prerequisites

- Docker + Docker Compose
- A Last9 account with OTLP credentials
- This repo cloned at `~/Projects/l9_otel_examples`

## Run

```sh
export OTEL_EXPORTER_OTLP_ENDPOINT="https://<your-cluster>.last9.io:443"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"

docker compose up --build
```

Exercise the API:

```sh
# Create
curl -X POST localhost:8080/users \
     -H 'content-type: application/json' \
     -d '{"name":"alice","email":"a@example.com"}'

# Read
curl localhost:8080/users
curl localhost:8080/users/1

# Update
curl -X PUT localhost:8080/users/1 \
     -H 'content-type: application/json' \
     -d '{"name":"alice b."}'

# Delete
curl -X DELETE localhost:8080/users/1

# Slow query (pg_sleep) — visible in trace UI by duration
curl localhost:8080/users/slow
```

In the Last9 traces UI you should see:

- A `GET /users` Gin span with a child `select users` GORM span and a
  grandchild `postgres.query` SQL span.
- A long (~500ms) `select` span on the `GET /users/slow` request.
- 404 lookups (`GET /users/9999`) keeping `STATUS_CODE_UNSET` — the upstream
  plugin's default skip-list swallows `gorm.ErrRecordNotFound`.

## Endpoints

| Method | Path             | What it does                                     |
| ------ | ---------------- | ------------------------------------------------ |
| GET    | `/users`         | List                                             |
| POST   | `/users`         | Create                                           |
| GET    | `/users/:id`     | Find one (returns 404 → no error span status)    |
| PUT    | `/users/:id`     | Update                                           |
| DELETE | `/users/:id`     | Delete                                           |
| GET    | `/users/slow`    | Raw `pg_sleep(0.5)` — visible by span duration   |

## Local development without Docker

```sh
docker compose up postgres -d
DATABASE_URL="postgres://postgres:postgres@localhost:5432/users?sslmode=disable" \
  go run .
```
