# Handling Large Logs in AWS ECS Fargate with Last9

This example demonstrates how to handle large logs (>100KB) in AWS ECS Fargate and forward them to Last9 using OpenTelemetry, solving the AWS Fargate 16KB log buffer limitation.

## Table of Contents

- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Integration Steps](#integration-steps)
- [Configuration Reference](#configuration-reference)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## The Problem

AWS Fargate has a **fixed 16KB runtime buffer limit** for container stdout/stderr. When your application writes logs larger than 16KB:

1. Docker runtime **splits the log** into multiple chunks (16KB each)
2. Each chunk gets metadata: `partial_message`, `partial_id`, `partial_ordinal`, `partial_last`
3. Without reassembly, these appear as **separate incomplete log entries** in your observability platform
4. JSON parsing fails on partial chunks, breaking log analysis

**The 16KB limit cannot be increased** - it's a hard AWS Fargate limitation.

## The Solution

Use **AWS FireLens (Fluent Bit)** with a multiline filter to reassemble split logs before forwarding to OpenTelemetry Collector:

1. Fluent Bit captures log chunks with Docker metadata
2. Multiline filter detects `partial_message=true` and groups chunks by `partial_id`
3. Chunks are concatenated in order until `partial_last=true`
4. Complete log is forwarded to OTEL Collector
5. OTEL Collector exports to Last9 with full log intact

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    ECS Fargate Task                     │
│                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │   Your   │───▶│ log-router   │───▶│    otel-     │ │
│  │   App    │    │ (Fluent Bit) │    │  collector   │ │
│  │          │    │   Multiline  │    │              │ │
│  │  Writes  │    │    Filter    │    │  Metrics +   │ │
│  │ >100KB   │    │  Reassembles │    │    Logs      │ │
│  │  logs    │    │  split logs  │    │              │ │
│  └──────────┘    └──────────────┘    └──────────────┘ │
│                                              │          │
└──────────────────────────────────────────────┼──────────┘
                                               │
                                               │ OTLP/HTTPS
                                               ▼
                                       ┌──────────────┐
                                       │    Last9     │
                                       └──────────────┘
```

**Data Flow:**
1. **Your App** → Writes large JSON logs to stdout
2. **log-router** → Fluent Bit reassembles split logs using multiline filter
3. **otel-collector** → Receives complete logs + collects ECS metrics
4. **Last9** → Receives complete, parseable logs and metrics

## Prerequisites

- Existing ECS Fargate cluster with running application
- AWS CLI configured
- Docker installed locally
- Last9 account with OTLP credentials
- Basic knowledge of ECS task definitions

## Integration Steps

### Step 1: Create Custom Fluent Bit Image

Create a file named `extra.conf`:

```ini
[FILTER]
    Name                multiline
    Match               *-firelens-*
    multiline.key_content log
    mode                partial_message
```

Create `Dockerfile.fluentbit`:

```dockerfile
FROM amazon/aws-for-fluent-bit:latest

# Copy custom Fluent Bit configuration
COPY extra.conf /fluent-bit/etc/extra.conf
```

Build and push to ECR:

```bash
# Set variables
export AWS_REGION=<your-region>
export AWS_ACCOUNT_ID=<your-account-id>
export ECR_REPO_FLUENTBIT=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/your-app-fluentbit

# Authenticate to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create repository
aws ecr create-repository --repository-name your-app-fluentbit --region $AWS_REGION

# Build and push
docker build --platform linux/amd64 -f Dockerfile.fluentbit -t ${ECR_REPO_FLUENTBIT}:latest .
docker push ${ECR_REPO_FLUENTBIT}:latest
```

### Step 2: Get Last9 Credentials

1. Log into your Last9 dashboard
2. Navigate to Settings → Integrations → OTLP
3. Copy your OTLP endpoint (e.g., `YOUR_OTLP_ENDPOINT`)
4. Copy your credentials (username and password)
5. Encode credentials:

```bash
echo -n "your-username:your-password" | base64
# Output: <base64-encoded-credentials>
```

### Step 3: Create OTEL Collector Configuration

Create `otel-config.yaml`:

```yaml
receivers:
  # Collect ECS container metrics
  awsecscontainermetrics:
    collection_interval: 60s

  # Receive logs from Fluent Bit
  fluentforward:
    endpoint: 0.0.0.0:8006

  # Accept OTLP (optional, for traces)
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  # Transform ECS metrics to add resource attributes
  transform/ecsmetrics:
    metric_statements:
      - context: datapoint
        statements:
          - set(attributes["aws.ecs.cluster.name"], resource.attributes["aws.ecs.cluster.name"])
          - set(attributes["aws.ecs.task.family"], resource.attributes["aws.ecs.task.family"])
          - set(attributes["aws.ecs.task.arn"], resource.attributes["aws.ecs.task.arn"])
          - set(attributes["cloud.region"], resource.attributes["cloud.region"])
          - set(attributes["container.name"], resource.attributes["container.name"])

  # Transform logs from Fluent Bit
  transform/firelens:
    error_mode: ignore
    log_statements:
      - context: log
        statements:
          # Set resource attributes from Fluent Bit metadata
          - set(resource.attributes["container_name"], attributes["container_name"]) where attributes["container_name"] != nil
          - set(resource.attributes["container_id"], attributes["container_id"]) where attributes["container_id"] != nil
          - set(resource.attributes["service.name"], attributes["container_name"]) where attributes["container_name"] != nil

          # Clean up metadata
          - delete_key(attributes, "container_id")
          - delete_key(attributes, "container_name")

  # Batch for efficient export
  batch:
    send_batch_max_size: 1000
    send_batch_size: 1000
    timeout: 10s

  # Detect ECS resource attributes
  resourcedetection:
    detectors: [ecs]

exporters:
  otlp/last9:
    endpoint: "<YOUR_LAST9_OTLP_ENDPOINT>"
    headers:
      "Authorization": "Basic <YOUR_BASE64_CREDENTIALS>"
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 5000

service:
  pipelines:
    metrics:
      receivers: [awsecscontainermetrics]
      processors: [batch, resourcedetection, transform/ecsmetrics]
      exporters: [otlp/last9]

    logs:
      receivers: [fluentforward]
      processors: [transform/firelens, batch, resourcedetection]
      exporters: [otlp/last9]
```

**Replace placeholders:**
- `<YOUR_LAST9_OTLP_ENDPOINT>` - Your Last9 OTLP endpoint
- `<YOUR_BASE64_CREDENTIALS>` - Your base64-encoded credentials from Step 2

### (Optional) Step 4: Create CloudWatch Log Groups

```bash
aws logs create-log-group --log-group-name /ecs/log-router --region $AWS_REGION
aws logs create-log-group --log-group-name /ecs/otel-collector --region $AWS_REGION
```

### Step 5: Update Task Definition

Update your existing task definition JSON to add two new containers and modify your app container's logging configuration.

**Add to `containerDefinitions` array:**

```json
{
  "containerDefinitions": [
    {
      "name": "your-app",
      "image": "<your-app-image>",
      "essential": true,
      "logConfiguration": {
        "logDriver": "awsfirelens",
        "options": {
          "Name": "forward",
          "Host": "127.0.0.1",
          "Port": "8006"
        }
      },
      "dependsOn": [
        {
          "containerName": "log-router",
          "condition": "START"
        },
        {
          "containerName": "otel-collector",
          "condition": "START"
        }
      ]
    },
    {
      "name": "log-router",
      "image": "<your-account-id>.dkr.ecr.<region>.amazonaws.com/your-app-fluentbit:latest",
      "essential": false,
      "firelensConfiguration": {
        "type": "fluentbit",
        "options": {
          "enable-ecs-log-metadata": "true",
          "config-file-type": "file",
          "config-file-value": "/fluent-bit/etc/extra.conf"
        }
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/log-router",
          "awslogs-region": "<your-region>",
          "awslogs-stream-prefix": "firelens"
        }
      }
    },
    {
      "name": "otel-collector",
      "image": "otel/opentelemetry-collector-contrib:latest",
      "essential": false,
      "command": ["--config", "env:OTEL_CONFIG"],
      "portMappings": [
        {
          "containerPort": 4317,
          "protocol": "tcp",
          "name": "otel-collector-4317-grpc"
        },
        {
          "containerPort": 4318,
          "protocol": "tcp",
          "name": "otel-collector-4318-http"
        }
      ],
      "environment": [
        {
          "name": "OTEL_CONFIG",
          "value": "<paste-entire-otel-config.yaml-contents-here-as-string>"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/otel-collector",
          "awslogs-region": "<your-region>",
          "awslogs-stream-prefix": "otel"
        }
      }
    }
  ]
}
```

**Key changes to your app container:**
1. Change `logDriver` from `awslogs` to `awsfirelens`
2. Configure forward output to port `8006`
3. Add `dependsOn` to ensure log-router and otel-collector start first

**To convert YAML to inline string for OTEL_CONFIG:**
```bash
# Read the file and create properly escaped JSON string
cat otel-config.yaml | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g'
```

Or copy the YAML content directly as shown in the example file `task-definition-with-otel.json`.

### Step 6: Register and Deploy

```bash
# Register new task definition
aws ecs register-task-definition --cli-input-json file://task-definition.json --region $AWS_REGION

# Update your service to use new task definition
aws ecs update-service \
  --cluster <your-cluster-name> \
  --service <your-service-name> \
  --task-definition <your-task-family>:<new-revision> \
  --force-new-deployment \
  --region $AWS_REGION
```

## Configuration Reference

### extra.conf - Fluent Bit Multiline Filter

```ini
[FILTER]
    Name                multiline          # Use multiline filter plugin
    Match               *-firelens-*       # Apply to all FireLens logs
    multiline.key_content log              # Field containing log content
    mode                partial_message    # Detect Docker partial markers
```

### Verify in Last9

1. Log into Last9 dashboard
2. Go to **Logs** section
3. Filter by `service.name = "your-app"`
4. Verify you see **complete logs**, not split chunks
5. Check that large logs (>100KB) appear as single entries

### Verify Metrics

In Last9, navigate to **Metrics** and check for:
- `container.cpu.usage`
- `container.memory.usage`
- Filter by `aws.ecs.cluster.name = "<your-cluster>"`