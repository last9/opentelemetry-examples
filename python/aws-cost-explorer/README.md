# AWS Cost Explorer → Last9

Sends AWS cost metrics to Last9 using the Cost Explorer API. No S3 bucket or CUR setup required — data flows within minutes.

## Prerequisites

- AWS account with billing access
- [Last9 OTLP credentials](https://app.last9.io/integrations)

## Deploy with CloudFormation (recommended)

No CLI or local setup needed — deploy directly from the AWS console.

1. Open [CloudFormation → Create stack](https://console.aws.amazon.com/cloudformation/home#/stacks/create)
2. Upload `cloudformation.yaml`
3. Fill in `OtlpHeaders` with your Last9 auth header
4. Click **Create stack**

CloudFormation creates the IAM role, Lambda function, and EventBridge daily schedule automatically.

Test after deploy:
```bash
aws lambda invoke --function-name aws-cost-reporter /tmp/out.json && cat /tmp/out.json
```

## Deploy with AWS CLI

Requires AWS CLI configured locally:

```bash
OTLP_HEADERS="Authorization=Basic <your-last9-token>" ./deploy.sh
```

## Run with Docker (local testing)

```bash
cp .env.example .env
# Fill in AWS credentials and OTLP_HEADERS
docker compose up
```

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `OTLP_HEADERS` | Yes | — | Last9 auth header (`Authorization=Basic <token>`) |
| `AWS_ACCESS_KEY_ID` | No* | — | AWS access key (Docker only) |
| `AWS_SECRET_ACCESS_KEY` | No* | — | AWS secret key (Docker only) |
| `AWS_DEFAULT_REGION` | No | `us-east-1` | AWS region |
| `DAYS_BACK` | No | `30` | Days of history to fetch per run |
| `POLL_INTERVAL_SECONDS` | No | `86400` | Re-poll interval for Docker mode |
| `OTEL_SERVICE_NAME` | No | `aws-cost-reporter` | Service name in Last9 |

\* Lambda uses the attached IAM role — no credentials needed.

## Metrics

| Metric | Unit | Dimensions |
|---|---|---|
| `aws.cost.unblended` | USD | `aws.service`, `aws.account.id`, `aws.region` |
| `aws.cost.amortized` | USD | same — RI and Savings Plan effective rates applied |

## Verification

After the Lambda runs, query `aws.cost.unblended` in [Last9 Metrics](https://app.last9.io/metrics) and group by `aws.service`.

---

> **Need resource-level granularity or cost allocation tags?**
> Use the [AWS CUR integration](../aws-cur/) instead — it reads Cost and Usage Report
> parquet files from S3 for line-item detail and custom tag dimensions.
