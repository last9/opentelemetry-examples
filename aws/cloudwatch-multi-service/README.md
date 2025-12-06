# AWS CloudWatch Multi-Service Log Collection → Last9

Comprehensive example for collecting logs from multiple AWS services (Amazon Connect, Lambda, Lex, API Gateway, EventBridge, S3) using OpenTelemetry Collector and forwarding to Last9.

## Overview

This integration demonstrates unified log collection from AWS CloudWatch Logs across multiple services without requiring code changes to your applications. Perfect for chatbot platforms, microservices architectures, or any multi-service AWS deployment.

### What Gets Collected

- **Amazon Connect**: Contact flow logs from all flows
- **AWS Lambda**: Function execution logs from all Lambda functions
- **Amazon Lex**: Bot conversation logs from all bots
- **API Gateway**: REST/HTTP API execution logs
- **EventBridge**: Event bus logs (if enabled)
- **S3**: Access logs (if CloudWatch integration enabled)

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                        AWS Services                            │
│                                                                │
│  ┌────────────┐  ┌─────────┐  ┌──────┐  ┌──────────┐         │
│  │  Connect   │  │ Lambda  │  │ Lex  │  │ API GW/  │         │
│  │ (n flows)  │  │(n funcs)│  │(n bots)│ EventBridge│        │
│  └─────┬──────┘  └────┬────┘  └───┬──┘  └────┬─────┘         │
│        │              │            │           │                │
│        └──────────────┴────────────┴───────────┘                │
│                       │                                         │
│             ┌─────────▼──────────┐                             │
│             │  CloudWatch Logs   │                             │
│             │  (Multiple Groups) │                             │
│             └─────────┬──────────┘                             │
│                       │                                         │
│              ┌────────▼──────────┐                             │
│              │ OTEL Collector    │                             │
│              │ (EC2 or ECS)      │                             │
│              │ - awscloudwatch   │                             │
│              │   receiver        │                             │
│              │ - autodiscovery   │                             │
│              │ - log enrichment  │                             │
│              └────────┬──────────┘                             │
│                       │                                         │
└───────────────────────┼─────────────────────────────────────────┘
                        │ OTLP/HTTPS
                        │
                 ┌──────▼────────┐
                 │  Last9 OTLP   │
                 │   Endpoint    │
                 └───────────────┘
```

## Quick Start

### Prerequisites

- AWS Account with CloudWatch Logs enabled
- Last9 account with OTLP credentials
- For local testing: Docker and Docker Compose

### Option 1: Local Testing with Docker Compose (Recommended First Step)

Test the configuration locally with LocalStack before deploying to AWS:

```bash
# 1. Copy environment variables
cp .env.example .env

# 2. Edit .env with your Last9 credentials
vi .env  # or your preferred editor

# 3. Start the stack
docker-compose up -d

# 4. Check logs
docker-compose logs -f otel-collector

# 5. Verify log generation
docker-compose logs log-generator

# 6. Stop the stack
docker-compose down
```

LocalStack will simulate all AWS services and generate test logs every 30 seconds.

### Option 2: Deploy to AWS with Terraform (Production)

```bash
# 1. Navigate to Terraform directory
cd terraform/ec2-deployment

# 2. Copy and edit terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars  # Fill in your values

# 3. Initialize Terraform
terraform init

# 4. Review the plan
terraform plan

# 5. Deploy
terraform apply

# 6. Get outputs
terraform output
```

#### Required Terraform Variables

Edit `terraform.tfvars` with your values:

```hcl
# Last9 Configuration (REQUIRED)
last9_otlp_endpoint = "https://otlp.last9.io:443"
last9_auth_header   = "Basic <YOUR_BASE64_ENCODED_CREDENTIALS>"

# CloudWatch Log Groups (REQUIRED - customize for your services)
cloudwatch_log_group_names = [
  "/aws/connect/your-connect-instance",
  "/aws/lambda/your-lambda-function",
  "/aws/lex/your-lex-bot"
]
```

## Configuration

### CloudWatch Log Group Discovery

The OTEL Collector supports two methods for discovering log groups:

#### 1. Autodiscovery (Recommended)

Automatically discovers all log groups matching a prefix:

```yaml
awscloudwatch:
  logs:
    groups:
      autodiscover:
        limit: 100
        prefix: /aws/  # Discovers all AWS service logs
```

#### 2. Named Log Groups

Explicitly list log groups:

```yaml
awscloudwatch:
  logs:
    groups:
      named:
        /aws/connect/aha_prod
        /aws/lambda/aha_prod_auth_handler
        /aws/lex/aha_prod_main_bot
```

### Log Group Naming Conventions

AWS services create CloudWatch log groups with these patterns:

| Service | Log Group Pattern | Example |
|---------|-------------------|---------|
| **Amazon Connect** | `/aws/connect/<instance-alias>` | `/aws/connect/aha_prod` |
| **AWS Lambda** | `/aws/lambda/<function-name>` | `/aws/lambda/auth_handler` |
| **Amazon Lex** | `/aws/lex/<bot-name>` | `/aws/lex/main_bot` |
| **API Gateway** | `/aws/apigateway/<api-name>` | `/aws/apigateway/prod_api` |
| **EventBridge** | `/aws/events/<event-bus-name>` | `/aws/events/default` |
| **S3** | `/aws/s3/<bucket-name>` | `/aws/s3/access-logs` |

### Environment Variables

All deployment methods support these environment variables:

```bash
# Last9 Configuration
LAST9_OTLP_ENDPOINT=https://otlp.last9.io:443
LAST9_AUTH_HEADER="Basic <base64-credentials>"

# AWS Configuration
AWS_REGION=us-east-1

# OTEL Collector Configuration
OTEL_SERVICE_NAME=aws-cloudwatch-collector
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,customer=my-company
```

## Deployment Options

### 1. EC2 Instance (Recommended for Most Use Cases)

**Pros:**
- Simple to manage
- Predictable costs ($10-15/month for t3.small)
- Easy SSH access for debugging
- Good for 100-500 log groups

**Terraform deployment:** See [terraform/ec2-deployment/](terraform/ec2-deployment/)

#### Manual EC2 Deployment

If you prefer manual setup without Terraform:

```bash
# 1. Launch Amazon Linux 2023 instance (t3.small recommended)
# 2. Attach IAM role with CloudWatch Logs permissions
# 3. SSH to instance

# 4. Download and install OTEL Collector
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.118.0/otelcol-contrib_0.118.0_linux_amd64.rpm
sudo rpm -ivh otelcol-contrib_0.118.0_linux_amd64.rpm

# 5. Copy configuration
sudo cp otel-collector-config.yaml /etc/otelcol-contrib/config.yaml

# 6. Edit config with your Last9 credentials
sudo vi /etc/otelcol-contrib/config.yaml

# 7. Start service
sudo systemctl start otelcol-contrib
sudo systemctl enable otelcol-contrib

# 8. Check status
sudo systemctl status otelcol-contrib
sudo journalctl -u otelcol-contrib -f
```

### 2. ECS Fargate (Coming Soon)

**Pros:**
- Serverless (no server management)
- Auto-scaling
- Good for highly variable workloads

**Cons:**
- Higher cost (~$25-40/month minimum)
- More complex setup

Terraform deployment: See [terraform/ecs-fargate-deployment/](terraform/ecs-fargate-deployment/)

### 3. Existing Infrastructure

Deploy on your existing EC2 instances (e.g., where CCB2 is running):

```bash
# Follow manual EC2 deployment steps above
# OTEL Collector uses ~100MB RAM and <1% CPU
```

## IAM Permissions

### Required IAM Policy

Attach this policy to the EC2 instance role or ECS task role:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchLogsRead",
            "Effect": "Allow",
            "Action": [
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:FilterLogEvents",
                "logs:GetLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
```

### Optional: Restrict to Specific Log Groups

For better security, restrict to specific log group prefixes:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:FilterLogEvents",
                "logs:GetLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:123456789012:log-group:/aws/connect/aha_prod*",
                "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/aha_prod*",
                "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lex/aha_prod*"
            ]
        }
    ]
}
```

## Cost Optimization

### CloudWatch Logs Retention

By default, CloudWatch Logs retention is set to "Never Expire", which can be expensive. Reduce costs by:

1. **Set Retention Period**: 14 days for most logs
2. **Archive to S3**: Move older logs to S3 for compliance

Use the included script:

```bash
./scripts/setup-retention-and-archive.sh \
  --retention-days 14 \
  --log-group-prefix /aws/connect/aha_prod \
  --archive-bucket my-logs-archive \
  --region us-east-1
```

### Cost Breakdown

| Component | Monthly Cost (Estimate) |
|-----------|-------------------------|
| **EC2 t3.small** | $15 (us-east-1, 730 hours) |
| **Data Transfer** | $1-5 (depends on log volume) |
| **CloudWatch Logs (14-day retention)** | $0.50/GB ingested, $0.03/GB stored |
| **S3 Archive (Glacier Deep Archive)** | $0.00099/GB/month |
| **Total** | ~$20-30/month for typical chatbot platform |

**Potential Savings:**
- Setting 14-day retention instead of "Never Expire": **Save 50-80%** on CloudWatch costs
- S3 archival: **Save 99%** on long-term storage costs

## Verification and Monitoring

### Health Check

```bash
# Check OTEL Collector health
curl http://<collector-ip>:13133

# Expected output: {"status":"Server available","upSince":"..."}
```

### View OTEL Collector Logs

**EC2:**
```bash
sudo journalctl -u otelcol-contrib -f
```

**Docker:**
```bash
docker-compose logs -f otel-collector
```

### Check Last9 Dashboard

1. Log in to Last9
2. Navigate to **Logs** section
3. Filter by:
   - `service.name = "cloudwatch-logs"`
   - `source = "cloudwatch"`
   - `customer.platform = "aha_chatbot"` (if configured)

### Verify Log Collection

Look for these attributes in Last9:

| Attribute | Description | Example |
|-----------|-------------|---------|
| `aws.log.group.names` | CloudWatch log group | `/aws/lambda/auth_handler` |
| `aws.service` | AWS service type | `lambda` |
| `aws.resource.name` | Resource name | `auth_handler` |
| `source` | Log source | `cloudwatch` |

## Troubleshooting

### Logs Not Appearing in Last9

**1. Check OTEL Collector is running:**
```bash
sudo systemctl status otelcol-contrib
```

**2. Check OTEL Collector logs for errors:**
```bash
sudo journalctl -u otelcol-contrib -n 100
```

**3. Verify IAM permissions:**
```bash
# Test CloudWatch Logs access
aws logs describe-log-groups --log-group-name-prefix /aws/connect/
```

**4. Test Last9 connectivity:**
```bash
curl -v https://otlp.last9.io
```

**5. Enable debug logging:**

Edit `/etc/otelcol-contrib/config.yaml`:
```yaml
exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    logs:
      exporters: [debug, otlp/last9]  # Add debug exporter
  telemetry:
    logs:
      level: debug  # Enable debug logging
```

Restart: `sudo systemctl restart otelcol-contrib`

### High Memory Usage

If OTEL Collector is using too much memory:

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 256  # Reduce from 512
    spike_limit_mib: 64  # Reduce from 128

  batch:
    send_batch_size: 50000  # Reduce from 100000
```

### Slow Log Collection

If logs are delayed:

```yaml
awscloudwatch:
  logs:
    poll_interval: 1m  # Reduce from 2m (increases API costs)
```

## Customization

### Filter Specific Log Streams

Filter logs by stream name:

```yaml
awscloudwatch:
  logs:
    groups:
      autodiscover:
        streams:
          prefixes:
            - "2024/"  # Only collect logs from 2024
```

### Add Custom Attributes

Add custom tags to logs:

```yaml
processors:
  transform/custom:
    log_statements:
      - context: log
        statements:
          - set(attributes["team"], "platform")
          - set(attributes["cost_center"], "engineering")
          - set(attributes["environment"], "production")

service:
  pipelines:
    logs:
      processors: [transform/custom, batch]
```

### Filter Out Noisy Logs

Exclude specific log patterns:

```yaml
processors:
  filter/exclude_health_checks:
    logs:
      exclude:
        match_type: regexp
        record_attributes:
          - key: body
            value: ".*health.*check.*"

service:
  pipelines:
    logs:
      processors: [filter/exclude_health_checks, batch]
```

## Support and Documentation

- **Last9 Documentation**: https://docs.last9.io
- **OpenTelemetry Collector**: https://opentelemetry.io/docs/collector/
- **AWS CloudWatch Receiver**: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/awscloudwatchreceiver

## Related Integrations

- [AWS Lambda ADOT Integration](../../product-integrations/aws-lambda.md) - For Lambda trace instrumentation
- [AWS ECS FireLens Integration](../../product-integrations/aws-ecs-fargate-fluentbit-logs.md) - For ECS container logs
- [AWS S3 Log Ingestion](../../product-integrations/aws-s3.md) - For S3 access logs

## License

This example is provided as-is under the MIT License.
