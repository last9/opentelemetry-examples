# Python Lambda + DynamoDB with OpenTelemetry - Last9 Integration

A Chalice-based Lambda API that performs DynamoDB CRUD operations, fully traced via the AWS Distro for OpenTelemetry (ADOT) Python layer. No manual SDK setup — all DynamoDB spans are created automatically.

## How It Works

```
HTTP Request
  └── Chalice Lambda handler (ADOT creates root span)
        └── DynamoDB.GetItem / PutItem / DeleteItem / Scan
              (auto-instrumented by ADOT botocore layer)
                    └── Last9 via OTLP
```

The `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument` env var activates ADOT's zero-code instrumentation. Every `boto3` call to DynamoDB becomes a child span with attributes like `db.system`, `aws.dynamodb.table_names`, and `rpc.method`.

## Prerequisites

- Python 3.11+
- AWS CLI configured (`aws configure`)
- Chalice: `pip install chalice`
- Last9 account — get OTLP credentials from [Last9 Integrations](https://app.last9.io/integrations?integration=OpenTelemetry)

## Quick Start

### 1. Configure credentials

```bash
cp .env.example .env
# Edit .env with your AWS region and Last9 OTLP credentials
```

Update `.chalice/collector-config.yaml`:
```yaml
exporters:
  otlp:
    endpoint: otlp.last9.io:443
    headers:
      authorization: Basic <your-base64-credentials>
```

### 2. Install dependencies

```bash
pip install chalice boto3
```

### 3. Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

The script:
- Creates the `items` DynamoDB table (PAY_PER_REQUEST billing)
- Injects credentials into collector config
- Deploys via `chalice deploy`

### 4. Test the API

```bash
# Get the API URL from chalice deploy output, then:

# List all items
curl https://<api-id>.execute-api.<region>.amazonaws.com/dev/items

# Create an item
curl -X POST https://<api-id>.execute-api.<region>.amazonaws.com/dev/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Widget", "description": "A test item"}'

# Get by ID
curl https://<api-id>.execute-api.<region>.amazonaws.com/dev/items/<item-id>

# Delete
curl -X DELETE https://<api-id>.execute-api.<region>.amazonaws.com/dev/items/<item-id>
```

### 5. Verify traces in Last9

1. Log in to [Last9](https://app.last9.io)
2. Navigate to **Traces**
3. Filter by service name `lambda-dynamodb-otel`
4. Each request shows a root Lambda span with nested DynamoDB child spans

## Configuration

| Variable | Description | Example |
|---|---|---|
| `AWS_REGION` | AWS region | `ap-south-1` |
| `OTLP_ENDPOINT` | Last9 OTLP host | `otlp.last9.io` |
| `OTLP_AUTH_HEADER` | Last9 auth header | `Basic abc123==` |
| `OTEL_SERVICE_NAME` | Service name in traces | `lambda-dynamodb-otel` |
| `DEPLOY_STAGE` | Chalice stage | `dev` or `prod` |
| `DYNAMODB_TABLE` | DynamoDB table name | `items` |

## ADOT Layer ARNs

Replace the layer ARN in `.chalice/config.json` for your region:

| Region | Layer ARN |
|---|---|
| ap-south-1 | `arn:aws:lambda:ap-south-1:901920570463:layer:aws-otel-python-amd64-ver-1-25-0:1` |
| us-east-1 | `arn:aws:lambda:us-east-1:901920570463:layer:aws-otel-python-amd64-ver-1-25-0:1` |
| us-west-2 | `arn:aws:lambda:us-west-2:901920570463:layer:aws-otel-python-amd64-ver-1-25-0:1` |
| eu-west-1 | `arn:aws:lambda:eu-west-1:901920570463:layer:aws-otel-python-amd64-ver-1-25-0:1` |

Find the latest version at [ADOT Lambda Layers](https://aws-otel.github.io/docs/getting-started/lambda/lambda-python).

## Teardown

```bash
chalice delete --stage dev
aws dynamodb delete-table --table-name items --region ap-south-1
```
