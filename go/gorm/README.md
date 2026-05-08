# GORM with last9/go-agent

End-to-end example for [GORM v2](https://gorm.io) instrumented with the
[`last9/go-agent`](https://github.com/last9/go-agent) `instrumentation/gorm`
plugin. Every HTTP request produces a two-layer trace:

```
gin handler span
  └─ User.Query / User.Create / ... (gormtrace span)
        └─ postgres.query (otelsql span, wire SQL)
```

The GORM span carries ORM-level context (model, operation, table, code frame,
N+1 query count). The SQL span beneath it carries the wire statement. Together
they answer both "what business operation is this" and "what SQL did it issue".

## What this example demonstrates

- `last9/go-agent/instrumentation/gorm` plugin installation
- Two-layer wiring: `database.Open` (otelsql) → GORM postgres dialector
- OTel semconv v1.30.0 attributes (`db.system.name`, `db.query.text`,
  `db.operation.name`, `db.collection.name`)
- `WithSlowQueryThreshold` flagging slow queries with `slow=true` and a
  `slow_query` event
- `WithFrame` overriding the runtime stack walk for a given handler
- `WithQueryCounter` enabling per-trace `db.query_count` for N+1 detection

## Prerequisites

- Docker + Docker Compose
- A Last9 account with OTLP credentials
- This repo cloned at `~/Projects/l9_otel_examples` and the go-agent repo
  cloned at `~/Projects/go-agent` (the Dockerfile assumes that layout)

## Run

```sh
export OTEL_EXPORTER_OTLP_ENDPOINT="https://<your-cluster>.last9.io:443"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"

docker compose up --build
```

Then exercise the API:

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

# Slow query (pg_sleep) → triggers slow_query event
curl localhost:8080/users/slow
```

In the Last9 traces UI you should see:

- A `GET /users` Gin span with a child `User.Query` GORM span and a
  grandchild `postgres.query` SQL span.
- `code.namespace=users.List` on the GORM span for `GET /users` (set via
  `WithFrame`), the stack-walked default for the others.
- A `slow=true` attribute and a `slow_query` event on the
  `GET /users/slow` GORM span.

## Endpoints

| Method | Path             | What it does                                     |
| ------ | ---------------- | ------------------------------------------------ |
| GET    | `/users`         | List, with `WithFrame` + `WithQueryCounter`      |
| POST   | `/users`         | Create                                           |
| GET    | `/users/:id`     | Find one (returns 404 → no error span status)    |
| PUT    | `/users/:id`     | Update                                           |
| DELETE | `/users/:id`     | Delete                                           |
| GET    | `/users/slow`    | Raw `pg_sleep(0.5)` to trip slow_query           |

## Note on the replace directive

While the `instrumentation/gorm` package is unreleased, `go.mod` carries a
`replace github.com/last9/go-agent => ../../../go-agent` line so the example
builds against the local branch. Once the package ships in a tagged go-agent
release, drop the replace and pin to the version.

## Local development without Docker

```sh
# Start just postgres
docker compose up postgres -d

# Local replace path resolves to ~/Projects/go-agent
go run .
```
