# CloudWatch Metric Enrichment Lambda

AWS Lambda function that enriches CloudWatch Metric Stream data with AWS resource tags before delivery to Last9 via Kinesis Data Firehose.

## Architecture

```
CloudWatch Metrics → Metric Streams (OTel 1.0) → Kinesis Data Firehose → Lambda (enrich) → Firehose → Last9
```

The Lambda intercepts OTLP records in the Firehose transformation step, extracts dimensions from the OTel 1.0 `Dimensions` KvlistValue attribute, looks up AWS resource tags via the Resource Groups Tagging API, and injects them as metric attributes with the `aws_tag_` prefix.

## Prerequisites

- Go 1.21+
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
- AWS account with permissions for Lambda, IAM, STS, and Resource Groups Tagging API
- CloudWatch Metric Stream configured with OTel 1.0 output format

## Quick Start

### 1. Build and Test

```bash
make test     # Run all tests with race detection
make build    # Produces arm64 Linux binary
```

### 2. Deploy with SAM

```bash
sam build
sam deploy \
  --stack-name last9-cw-metric-enrichment \
  --region <your-aws-region> \
  --resolve-s3 \
  --capabilities CAPABILITY_IAM \
  --no-confirm-changeset
```

### 3. Configure Environment Variables

SAM CLI mangles JSON parameter values. Set `CROSS_ACCOUNT_ROLES` via the AWS CLI after deployment:

```bash
aws lambda update-function-configuration \
  --function-name last9-cloudwatch-metric-enrichment \
  --environment '{
    "Variables": {
      "CROSS_ACCOUNT_ROLES": "{}",
      "TAG_CACHE_TTL": "1h",
      "LOG_LEVEL": "info",
      "CONTINUE_ON_TAG_FAILURE": "true"
    }
  }'
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `CROSS_ACCOUNT_ROLES` | `{}` | JSON: `{"accountId": "roleArn"}` |
| `TAG_CACHE_TTL` | `1h` | Go duration for file cache expiry |
| `LOG_LEVEL` | `info` | `info` or `debug` |
| `CONTINUE_ON_TAG_FAILURE` | `true` | Skip enrichment vs fail on API errors |

## OTel Format Support

**OpenTelemetry 1.0** (recommended) — dimensions are in a `Dimensions` attribute of type `KvlistValue`, enabling per-resource tag enrichment.

**OpenTelemetry 0.7** (fallback) — metric identity is in the `metric.Name` field, datapoint attributes are empty. Resource tag enrichment is not possible without dimensions for resource matching.

## Verification

Check CloudWatch Logs for the Lambda function:

```bash
aws logs tail /aws/lambda/last9-cloudwatch-metric-enrichment --since 5m --follow
```

Metrics arriving in Last9 should contain `aws_tag_*` labels (e.g., `aws_tag_Name`, `aws_tag_Environment`).

## IAM Permissions

The Lambda needs:
- `tag:GetResources` — fetch resource tags
- `sts:GetCallerIdentity` — detect current account
- `sts:AssumeRole` — cross-account tag access

Cross-account source roles need `tag:GetResources` with a trust policy for the Lambda's account.

## Project Structure

```
├── main.go              # Lambda entrypoint
├── handler.go           # Firehose event handler
├── otlp/                # OTLP protobuf decode/encode + OTel 0.7 compat layer
├── enricher/            # Core enrichment: dimension extraction + tag lookup
├── associator/          # CloudWatch metric → AWS resource mapping (via YACE)
├── crossaccount/        # Cross-account STS role assumption
├── template.yaml        # SAM/CloudFormation template
└── Makefile
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No `aws_tag_*` labels on metrics | Metric Stream uses OTel 0.7 (no dimensions) | Switch to OTel 1.0: `--output-format opentelemetry1.0` |
| Some metrics missing `aws_tag_*` | Aggregate dimensions can't match a specific resource | Expected — only primary dimensions (`InstanceId`, `DBInstanceIdentifier`) match |
| Metrics arrive without enrichment | Lambda is crashing | Check logs: `aws logs tail /aws/lambda/last9-cloudwatch-metric-enrichment --since 5m` |
| Metric Stream shows 0 MetricUpdate | IAM role not yet propagated | Stop and restart the Metric Stream (takes 1-2 min) |

## Additional Resources

- [Last9 Documentation](https://last9.io/docs/)
- [CloudWatch Metric Streams](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
