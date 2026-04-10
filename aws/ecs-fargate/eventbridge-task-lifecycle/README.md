# ECS Lifecycle Events → Last9 via EventBridge

Captures ECS lifecycle events using Amazon EventBridge and forwards them to Last9 as searchable logs. Covers the full task lifecycle, service actions (deployments, scaling), and deployment outcomes.

## Event Types Captured

| Event | Detail Type | What it tells you |
|-------|------------|-------------------|
| **Task State Change** | `ECS Task State Change` | Full task lifecycle: PROVISIONING → RUNNING → STOPPED. Includes stop reason, exit codes. |
| **Service Action** | `ECS Service Action` | Deployments starting, scaling, steady-state reached, circuit breaker triggered. |
| **Deployment State Change** | `ECS Deployment State Change` | Deployment progress: IN_PROGRESS → COMPLETED or FAILED. |

All three are enabled by default. Toggle individually via parameters.

## Two Deployment Options

| Option | Template | Use when |
|--------|----------|----------|
| **No-Lambda** (recommended) | `cloudformation-no-lambda.yaml` | Zero code — EventBridge posts directly to Last9 `/json/v2` |
| **Lambda** | `cloudformation.yaml` | Need structured OTLP logs with severity levels and per-container exit codes as attributes |

## Prerequisites

- AWS CLI configured with permissions for CloudFormation, IAM, EventBridge
- An ECS Fargate cluster
- Last9 account — credentials from **Settings → Integrations → Send Data**

## Quick Start

### Option A: No-Lambda (recommended)

```bash
aws cloudformation deploy \
  --template-file cloudformation-no-lambda.yaml \
  --stack-name last9-ecs-lifecycle \
  --parameter-overrides \
      Last9Host=<your-host>.last9.io \
      Last9Username=<username> \
      Last9Password=<password> \
  --capabilities CAPABILITY_NAMED_IAM
```

### Option B: Lambda (OTLP format)

```bash
# Encode credentials: echo -n "username:password" | base64
aws cloudformation deploy \
  --template-file cloudformation.yaml \
  --stack-name last9-ecs-lifecycle \
  --parameter-overrides \
      Last9OTLPEndpoint=https://<your-host>.last9.io/v1/logs \
      Last9AuthToken=<base64-credentials> \
  --capabilities CAPABILITY_NAMED_IAM
```

### Optional overrides

```bash
# Filter to a specific cluster
ECSClusterArn=arn:aws:ecs:us-east-1:123456789012:cluster/prod

# Disable specific event types
EnableTaskStateEvents=false
EnableServiceActionEvents=false
EnableDeploymentEvents=false
```

## Configuration

### No-Lambda Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `Last9Host` | Yes | — | Last9 hostname, e.g. `yourorg.last9.io` |
| `Last9Username` | Yes | — | Write username from Last9 Integrations |
| `Last9Password` | Yes | — | Write password from Last9 Integrations |
| `ServiceName` | No | `ecs-lifecycle` | `service_name` tag in Last9 Logs Explorer |
| `ECSClusterArn` | No | *(all clusters)* | Filter to a specific ECS cluster ARN |
| `EnableTaskStateEvents` | No | `true` | Capture task lifecycle events |
| `EnableServiceActionEvents` | No | `true` | Capture service action events |
| `EnableDeploymentEvents` | No | `true` | Capture deployment state changes |

### Lambda Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `Last9OTLPEndpoint` | Yes | — | OTLP HTTP endpoint, e.g. `https://otlp.last9.io/v1/logs` |
| `Last9AuthToken` | Yes | — | Base64-encoded `username:password` |
| `ECSClusterArn` | No | *(all clusters)* | Filter to a specific ECS cluster ARN |
| `EnableTaskStateEvents` | No | `true` | Capture task lifecycle events |
| `EnableServiceActionEvents` | No | `true` | Capture service action events |
| `EnableDeploymentEvents` | No | `true` | Capture deployment state changes |

## Verification

1. **Check rules are firing:**

   ```bash
   # Replace <stack-name> with your CloudFormation stack name
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Events \
     --metric-name TriggeredRules \
     --dimensions Name=RuleName,Value=last9-ecs-task-state-<stack-name> \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 --statistics Sum
   ```

2. **Check for delivery failures:**

   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Events \
     --metric-name FailedInvocations \
     --dimensions Name=RuleName,Value=last9-ecs-task-state-<stack-name> \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 --statistics Sum
   ```

3. **Search in Last9 Logs Explorer:**
   - No-Lambda: `service_name = "ecs-lifecycle"`
   - Lambda: filter by `event.name`:
     - `ecs.task.state_change` — task lifecycle events
     - `ecs.service.action` — service actions
     - `ecs.deployment.state_change` — deployment events

## Correlation with ECS Metrics

The `taskArn` field in lifecycle log entries matches the `aws_ecs_task_arn` metric label in Last9 ECS metrics. Use this to answer: "why did this task stop?" alongside "what were the resource metrics before it stopped?".

## Local Testing (Lambda variant)

```bash
export LAST9_OTLP_ENDPOINT=https://<your-host>.last9.io/v1/logs
export LAST9_AUTH=<base64-credentials>
python lambda/handler.py
```

Sends three sample events (task stop, service action, deployment complete) to your Last9 endpoint.

## Cleanup

```bash
aws cloudformation delete-stack --stack-name last9-ecs-lifecycle
```
