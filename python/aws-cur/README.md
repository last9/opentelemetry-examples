# AWS Cost and Usage Report → Last9

Exports AWS billing data from Cost and Usage Reports (CUR) to Last9 as OpenTelemetry metrics, broken down by service, account, and region.

## Prerequisites

- AWS account with Cost and Usage Reports enabled (S3 export, Parquet format)
- S3 bucket read access via IAM role or access key
- Last9 account with OTLP credentials

## Quick Start

1. **Enable CUR** in [AWS Billing → Cost & Usage Reports](https://us-east-1.console.aws.amazon.com/billing/home#/reports):
   - Report content: Include resource IDs
   - Time granularity: **Daily**
   - File format: **Parquet**
   - Note your bucket name, S3 prefix, and report name

2. **Configure:**
   ```bash
   cp .env.example .env
   # Edit .env — set CUR_S3_BUCKET, CUR_REPORT_NAME, and OTLP_HEADERS
   ```

3. **Run:**
   ```bash
   docker compose up
   ```

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `CUR_S3_BUCKET` | Yes | — | S3 bucket containing CUR files |
| `CUR_S3_PREFIX` | No | `""` | S3 path prefix before the report name |
| `CUR_REPORT_NAME` | Yes | — | Report name set in AWS Billing |
| `AWS_ACCESS_KEY_ID` | No* | — | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | No* | — | AWS secret key |
| `AWS_DEFAULT_REGION` | No | `us-east-1` | AWS region |
| `MONTHS_BACK` | No | `3` | Billing periods to process per run |
| `POLL_INTERVAL_SECONDS` | No | `3600` | Re-poll interval (CUR updates ~daily) |
| `OTLP_ENDPOINT` | No | `https://otlp.last9.io` | Last9 OTLP endpoint |
| `OTLP_HEADERS` | Yes | — | Last9 auth header from the dashboard |
| `OTEL_SERVICE_NAME` | No | `aws-cost-reporter` | Service name in Last9 |

\* Omit `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` when running on EC2/ECS/Lambda — boto3 uses the attached IAM role automatically.

## Metrics

| Metric | Unit | Dimensions |
|---|---|---|
| `aws.cost.unblended` | USD | `aws.service`, `aws.account.id`, `aws.region`, `aws.usage.type` |
| `aws.usage.quantity` | 1 | `aws.service`, `aws.account.id`, `aws.region`, `aws.usage.type` |

Each data point carries the actual billing date as its timestamp, enabling historical cost queries in Last9.

## IAM Policy

Minimum permissions for the S3 bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::my-company-cur-bucket",
      "arn:aws:s3:::my-company-cur-bucket/*"
    ]
  }]
}
```

## Verification

After startup, logs should show:

```
Exported N cost + N usage data points to Last9
```

Then query `aws.cost.unblended` in Last9 filtered by `aws.service` to see per-service cost breakdown.
