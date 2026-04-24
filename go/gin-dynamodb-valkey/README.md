# Gin + DynamoDB + Valkey

Go/Gin service instrumented with the Last9 Go Agent — emits distributed traces for Amazon DynamoDB (via `otelaws`) and Valkey (via `valkeyotel`).

## Prerequisites

- Go 1.24+
- Docker (for local DynamoDB + Valkey)
- AWS CLI (to seed the DynamoDB table)
- A Last9 account — see [Last9 docs](https://last9.io/docs) for OTLP endpoint and auth

## Quick Start

1. Copy env template and fill in your Last9 credentials:

   ```bash
   cp .env.example .env
   # edit .env, set OTEL_EXPORTER_OTLP_ENDPOINT + OTEL_EXPORTER_OTLP_HEADERS
   ```

2. Start local DynamoDB + Valkey, create the table, seed a row:

   ```bash
   docker compose up -d

   aws dynamodb create-table \
     --endpoint-url http://localhost:8000 --region us-east-1 \
     --table-name users \
     --attribute-definitions AttributeName=user_id,AttributeType=S \
     --key-schema AttributeName=user_id,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST

   aws dynamodb put-item \
     --endpoint-url http://localhost:8000 --region us-east-1 \
     --table-name users \
     --item '{"user_id":{"S":"u1"},"name":{"S":"Alice"}}'
   ```

3. Run the server:

   ```bash
   set -a && source .env && set +a
   go run .
   ```

4. Exercise the endpoints:

   ```bash
   curl -XPOST "http://localhost:8080/cache/hello?value=world"
   curl http://localhost:8080/cache/hello
   curl http://localhost:8080/users/u1
   ```

## Configuration

| Variable | Purpose |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=<your-last9-auth-value>` |
| `OTEL_SERVICE_NAME` | Service name shown in Trace Explorer |
| `OTEL_TRACES_SAMPLER` | `always_on` for dev |
| `OTEL_RESOURCE_ATTRIBUTES` | e.g. `deployment.environment=local` |
| `AWS_ENDPOINT_URL` | Omit in production — only needed for DynamoDB-local |
| `AWS_REGION` | AWS region |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Dummy values `local` / `local` for DynamoDB-local; use IAM in production |
| `VALKEY_ADDR` | Valkey host:port (default `localhost:6379`) |

## Verification

Open [Last9 Trace Explorer](https://app.last9.io/traces) and filter by `service.name = gin-dynamodb-valkey-example`. Each request produces a trace with this shape:

```
GET /users/:id                       (Gin server span)
└── DynamoDB.GetItem                 (otelaws client span)
    ├── aws.dynamodb.table_names = ["users"]
    ├── rpc.method = "GetItem"
    └── db.system = "dynamodb"

GET /cache/:key                      (Gin server span)
└── GET                              (valkeyotel client span)
    ├── db.system = "valkey"
    └── db.operation = "GET"
```

<details>
<summary>Production notes</summary>

- Drop `AWS_ENDPOINT_URL` when pointing at real AWS. SDK falls back to default endpoint resolution.
- Use IAM role credentials in production, not the `local`/`local` pair.
- For Valkey in production, set `VALKEY_ADDR` to your cluster. `valkeyotel.NewClient` accepts the full `valkey.ClientOption` struct for TLS, auth, sentinel, etc.

</details>

<details>
<summary>Troubleshooting</summary>

| Symptom | Cause |
|---|---|
| DynamoDB span missing `aws.dynamodb.table_names` | `WithAttributeSetter(DynamoDBAttributeSetter)` not passed to `AppendMiddlewares` |
| Valkey span missing or orphaned | Handler didn't pass `c.Request.Context()` into `valkeyClient.Do(...)` |
| No traces in Last9 | `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_HEADERS` not set before `agent.Start()` |
| `go build` fails on `valkeyotel` | `github.com/valkey-io/valkey-go/valkeyotel` is a separate submodule — ensure it's a top-level `require` in `go.mod` |

</details>
