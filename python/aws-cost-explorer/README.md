# AWS Cost Explorer → Last9

Sends AWS cost metrics to Last9 using the Cost Explorer API. No S3 bucket or CUR setup required — data flows within minutes.

## Prerequisites

- AWS account with billing access
- [Last9 OTLP credentials](https://app.last9.io/integrations)

## Setup

### 1. Create IAM policy

Attach this policy to the IAM user or role running the collector:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "ce:GetCostAndUsage",
    "Resource": "*"
  }]
}
```

### 2. Configure and run

```bash
cp .env.example .env
# Fill in AWS credentials and OTLP_HEADERS
docker compose up
```

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `AWS_ACCESS_KEY_ID` | No* | — | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | No* | — | AWS secret key |
| `AWS_DEFAULT_REGION` | No | `us-east-1` | AWS region |
| `DAYS_BACK` | No | `30` | Days of history to fetch per run |
| `POLL_INTERVAL_SECONDS` | No | `86400` | Re-poll interval (Cost Explorer updates ~daily) |
| `OTLP_HEADERS` | Yes | — | Last9 auth header (e.g. `Authorization=Basic <token>`) |
| `OTEL_SERVICE_NAME` | No | `aws-cost-reporter` | Service name in Last9 |

\* Skip on EC2/ECS/Lambda — the attached IAM role is used automatically.

## Metrics

| Metric | Unit | Dimensions |
|---|---|---|
| `aws.cost.unblended` | USD | `aws.service`, `aws.account.id`, `aws.region` |
| `aws.cost.amortized` | USD | same — RI and Savings Plan effective rates applied |

## Verification

Logs show:
```
Exported N unblended + N amortized data points to Last9
```

Then query `aws.cost.unblended` in [Last9 Metrics](https://app.last9.io/metrics) and group by `aws.service`.

---

> **Need resource-level granularity or cost allocation tags?**
> Use the [AWS CUR integration](../aws-cur/) instead — it reads Cost and Usage Report
> parquet files from S3 for line-item detail and custom tag dimensions.
