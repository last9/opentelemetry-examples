# Gin + DynamoDB + Valkey

Go/Gin service instrumented with the Last9 Go Agent — emits distributed traces for Amazon DynamoDB (via `otelaws`), Valkey (via `valkeyotel`), SQS long-poll workers, and outbound HTTP (via `httpagent`). Demonstrates `context.Context` propagation end-to-end so spans link into one tree per request.

## Prerequisites

- Go 1.22+
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
   curl "http://localhost:8080/external?url=https://httpbin.org/get"
   ```

## Context propagation

`main.go` threads `context.Context` from each gin handler through `Service` methods to every SDK call (DynamoDB, Valkey, SQS, outbound HTTP). This is what makes spans nest into a single trace per request. See the [Go Gin integration guide](https://last9.io/docs/integrations/golang-gin) for the full pattern + anti-patterns.

## Configuration

Replace every `<placeholder>` with your own values. `local`-only fields (marked with *) are for the docker-compose flow and should be removed in production.

| Variable | Example / Placeholder | Notes |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `<your-last9-otlp-endpoint>` | e.g. `https://otlp-aps1.last9.io:443` |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=<your-last9-auth-value>` | Copy from Last9 Integrations → OpenTelemetry |
| `OTEL_SERVICE_NAME` | `<your-service-name>` | Shown in Trace Explorer |
| `OTEL_TRACES_SAMPLER` | `always_on` \| `parentbased_traceidratio` | `always_on` for dev, sampled in prod |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment=<env>` | Add `service.version`, `service.namespace` as needed |
| `AWS_REGION` | `<your-aws-region>` | e.g. `us-east-1`, `ap-south-1` |
| `AWS_ENDPOINT_URL`* | `http://localhost:8000` | DynamoDB-local only. **Omit in production.** |
| `AWS_ACCESS_KEY_ID`* / `AWS_SECRET_ACCESS_KEY`* | `local` / `local` | DynamoDB-local only. Use IAM role / instance profile in production. |
| `DYNAMODB_TABLE` | `<your-table-name>` | Defaults to `users` if unset |
| `SQS_QUEUE_URL` | `<your-sqs-queue-url>` | Optional. When set, starts the SQS long-poll worker. |
| `VALKEY_ADDR` | `<host:port>` or `<host1:port,host2:port>` | Comma-separated for cluster / sentinel |
| `VALKEY_TLS` | `true` \| `false` | Set `true` for managed Valkey with encryption in transit |
| `VALKEY_USERNAME` | `<acl-username>` or empty | Managed Valkey with ACL (e.g. MemoryDB, Upstash) |
| `VALKEY_PASSWORD` | `<acl-password>` or empty | Managed Valkey with ACL / auth token |

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
<summary>Run against a production Valkey (any host)</summary>

The sample app works unchanged against any Valkey deployment — docker, managed, or self-hosted. Only env vars differ. RESP is the common wire protocol, so `valkey-go` speaks to all of them identically.

| Valkey host | `VALKEY_ADDR` | `VALKEY_TLS` | `VALKEY_USERNAME` | `VALKEY_PASSWORD` |
|---|---|---|---|---|
| Local docker-compose (this repo) | `localhost:6379` | `false` | *(empty)* | *(empty)* |
| Self-hosted plaintext | `<your-host>:6379` | `false` | *(empty)* | *(empty)* |
| Self-hosted with TLS + ACL | `<your-host>:6379` | `true` | `<acl-user>` | `<acl-password>` |
| AWS ElastiCache for Valkey | `<primary-endpoint>:6379` | `true` if in-transit encryption enabled, else `false` | *(empty unless RBAC)* | *(empty unless RBAC)* |
| AWS MemoryDB for Valkey | `<cluster-endpoint>:6379` | `true` | `<acl-user>` | `<acl-password>` |
| Upstash / Aiven / Redis Cloud | `<provider-host>:<port>` | `true` | `<provider-user>` | `<provider-token>` |
| Cluster / sentinel | `<host1>:6379,<host2>:6379,<host3>:6379` | per provider | per provider | per provider |

**Gotcha — AWS ElastiCache for Valkey specifically:**
- Terraform: use `aws_elasticache_replication_group`, not `aws_elasticache_cluster`. The latter errors with *"This API doesn't support Valkey engine"*.
- Default cluster has in-transit encryption enabled → set `VALKEY_TLS=true` or create the cluster with `transit_encryption_enabled = false`.

</details>

<details>
<summary>Deploy the app to AWS EC2 (IAM + systemd)</summary>

The sample app runs as a normal binary. On AWS EC2 the two concerns are **credentials** (use an instance profile, not static keys) and **systemd env parsing** (quote values that contain spaces).

**Minimum IAM policy** for the table you pass as `DYNAMODB_TABLE` (replace `<region>`, `<account>`, `<table>`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"],
    "Resource": "arn:aws:dynamodb:<region>:<account>:table/<table>"
  }]
}
```

Attach this to an IAM role, wrap in an instance profile, attach to the EC2 instance. Do **not** set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — the SDK auto-discovers instance-profile credentials via IMDS.

**systemd unit** (`/etc/systemd/system/gin-app.service`):

```ini
[Unit]
Description=gin-dynamodb-valkey
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/gin-app/gin-app
Restart=always
RestartSec=5
# Quote EVERY value. OTEL_EXPORTER_OTLP_HEADERS has a space
# ("Authorization=Basic <base64>") and systemd splits unquoted
# Environment= values on whitespace → silent truncation → 401.
Environment="OTEL_EXPORTER_OTLP_ENDPOINT=<your-last9-otlp-endpoint>"
Environment="OTEL_EXPORTER_OTLP_HEADERS=Authorization=<your-last9-auth-value>"
Environment="OTEL_SERVICE_NAME=<your-service-name>"
Environment="OTEL_TRACES_SAMPLER=always_on"
Environment="OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production"
Environment="AWS_REGION=<your-aws-region>"
Environment="DYNAMODB_TABLE=<your-table-name>"
Environment="VALKEY_ADDR=<your-valkey-host>:6379"
Environment="VALKEY_TLS=true"

[Install]
WantedBy=multi-user.target
```

**Security group minimums:**
- App SG: egress 443 to `0.0.0.0/0` (OTLP + AWS APIs); egress 6379 to Valkey SG.
- Valkey SG (if ElastiCache / self-hosted in same VPC): ingress 6379 from App SG only.

</details>

<details>
<summary>Troubleshooting</summary>

| Symptom | Cause |
|---|---|
| Spans not linked into one trace (orphan single-span traces) | See [span-linking troubleshooting in the product doc](https://last9.io/docs/integrations/golang-gin) — covers ctx propagation, outbound HTTP, SQS poller. |
| DynamoDB span missing `aws.dynamodb.table_names` | `WithAttributeSetter(DynamoDBAttributeSetter)` not passed to `AppendMiddlewares` |
| Valkey span missing or orphaned | Handler didn't pass `c.Request.Context()` into `valkeyClient.Do(...)` |
| No traces in Last9 | `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_HEADERS` not set before `agent.Start()` |
| `go build` fails on `valkeyotel` | `github.com/valkey-io/valkey-go/valkeyotel` is a separate submodule — ensure it's a top-level `require` in `go.mod` |
| 401 Unauthorized from OTLP exporter on systemd | `Environment=` value contains a space (`Authorization=Basic <b64>`) and is unquoted — systemd truncates it. Quote every `Environment=` value. |
| Valkey client hangs / `io: read/write on closed pipe` | Server has TLS enabled but `VALKEY_TLS` is unset (or vice versa). Match the client setting to the server. |

</details>
