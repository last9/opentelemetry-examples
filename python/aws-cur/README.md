# AWS Cost and Usage Report → Last9

Collects AWS billing data from Cost and Usage Reports (CUR) and sends it to Last9 as OpenTelemetry metrics.

## Prerequisites

- AWS account with billing access
- S3 bucket for CUR delivery
- [Last9 OTLP credentials](https://app.last9.io/integrations)

## Setup

### 1. Enable CUR in AWS

Go to [AWS Billing → Cost & Usage Reports](https://us-east-1.console.aws.amazon.com/billing/home#/reports) → **Create report**:

| Setting | Value |
|---|---|
| Time granularity | Daily |
| File format | **Parquet** |
| Report content | Include resource IDs |

Note the **bucket name**, **S3 prefix**, and **report name** — you'll need them below.

> CUR files appear in S3 within 24 hours of first setup.

### 2. Grant S3 read access

Attach this policy to the IAM user or role running the collector:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::<your-cur-bucket>",
      "arn:aws:s3:::<your-cur-bucket>/*"
    ]
  }]
}
```

### 3. Configure and run

```bash
cp .env.example .env
# Fill in CUR_S3_BUCKET, CUR_REPORT_NAME, AWS credentials, and OTLP_HEADERS
docker compose up
```

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `CUR_S3_BUCKET` | Yes | — | S3 bucket name |
| `CUR_REPORT_NAME` | Yes | — | Report name from AWS Billing |
| `CUR_S3_PREFIX` | No | `""` | S3 path prefix before the report name |
| `AWS_ACCESS_KEY_ID` | No* | — | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | No* | — | AWS secret key |
| `AWS_DEFAULT_REGION` | No | `us-east-1` | AWS region |
| `MONTHS_BACK` | No | `3` | Billing periods to process per run |
| `COST_ALLOCATION_TAGS` | No | `""` | Tag keys to add as `aws.tag.*` dimensions (e.g. `team,environment`) |
| `OTLP_HEADERS` | Yes | — | Last9 auth header (e.g. `Authorization=Basic <token>`) |
| `OTEL_SERVICE_NAME` | No | `aws-cost-reporter` | Service name in Last9 |

\* Skip on EC2/ECS/Lambda — the attached IAM role is used automatically.

## Metrics

| Metric | Unit | Dimensions |
|---|---|---|
| `aws.cost.unblended` | USD | `aws.service`, `aws.account.id`, `aws.region`, `aws.usage.type`, `aws.tag.*` |
| `aws.cost.amortized` | USD | same — RI and Savings Plan effective rates applied |
| `aws.usage.quantity` | 1 | `aws.service`, `aws.account.id`, `aws.region`, `aws.usage.type`, `aws.tag.*` |

`aws.tag.*` dimensions appear only when `COST_ALLOCATION_TAGS` is set and those tags are activated in [AWS Billing → Cost allocation tags](https://us-east-1.console.aws.amazon.com/billing/home#/tags).

## Verification

Confirm data is flowing:

```
Exported N unblended + N amortized + N usage data points to Last9
```

To test without a real AWS account:

```bash
OTLP_HEADERS="Authorization=Basic <token>" \
COST_ALLOCATION_TAGS=team,environment \
python test_local.py
```

Then query `aws.cost.unblended` in [Last9 Metrics](https://app.last9.io/metrics) and filter by `aws.service`.
