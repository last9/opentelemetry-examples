# AWS Airflow & Secrets Manager with OpenTelemetry Demo

This example demonstrates OpenTelemetry instrumentation for **Amazon Web Services** including:
- AWS MWAA (Managed Workflows for Apache Airflow) - DAG triggering and monitoring
- AWS Secrets Manager - Secure secret storage and retrieval

All telemetry data is sent to Last9 via OTLP, with support for LocalStack for local development.

## ✨ Features

### AWS Airflow (MWAA) Integration
- **Custom instrumentation** for `airflow.dag.trigger` operations
- **DAG execution monitoring** with proper span attributes
- **Mock support** for local development without AWS MWAA
- **Environment and DAG parameter support**

### AWS Secrets Manager Integration
- **Custom instrumentation** for `secretsmanager.secret.create` and `secretsmanager.secret.get` operations
- **Secure secret handling** with proper error recording
- **LocalStack support** for offline development
- **Full CRUD operations** on secrets

### Enhanced Configuration
- **Configurable service name** via `OTEL_SERVICE_NAME` environment variable
- **AWS resource detection** when running on EC2
- **LocalStack endpoint configuration** for local testing
- **Comprehensive error handling and span recording**

## API Endpoints

### Health Check
```bash
curl http://localhost:8080/health
```

### Secrets Manager Operations
```bash
# Create a secret
curl -X POST http://localhost:8080/secrets/create \
  -H "Content-Type: application/json" \
  -d '{
    "secret_name": "my-api-key",
    "secret_value": "super-secret-value"
  }'

# Retrieve a secret
curl http://localhost:8080/secrets/my-api-key
```

### Airflow Operations
```bash
# Trigger a DAG
curl -X POST http://localhost:8080/airflow/trigger \
  -H "Content-Type: application/json" \
  -d '{
    "environment_name": "my-airflow-env",
    "dag_id": "data_pipeline_dag",
    "parameters": {
      "start_date": "2024-01-01",
      "table_name": "user_events"
    }
  }'
```

## Prerequisites

- Go 1.23+
- AWS credentials (for production) or LocalStack (for local testing)
- Last9 account and credentials
- Docker and Docker Compose (for LocalStack)

## Quick Start

### 1. Install Dependencies

```bash
cd go/aws-airflow-secrets
go mod tidy
```

### 2. Set Up Environment Variables

#### For Last9 Integration

```bash
# Service name (customize as needed)
export OTEL_SERVICE_NAME="aws-airflow-secrets-demo"

# Last9 OTLP configuration
export OTEL_EXPORTER_OTLP_ENDPOINT="YOUR_LAST9_ENDPOINT"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <YOUR_LAST9_BASIC_AUTH_TOKEN>"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=demo,service.version=1.0.0"
```

#### For AWS (Production)

```bash
export AWS_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export MWAA_ENVIRONMENT_NAME="your-airflow-environment"
```

## Testing Options

### Option 1: LocalStack Testing (Recommended for Development)

LocalStack provides local emulation of AWS services for testing without incurring cloud costs.

#### 1. Create LocalStack Configuration

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  localstack:
    container_name: localstack_aws
    image: localstack/localstack:latest
    ports:
      - "4566:4566"
    environment:
      - SERVICES=secretsmanager,mwaa
      - DEBUG=${DEBUG:-0}
      - PERSISTENCE=${PERSISTENCE:-0}
      - DOCKER_HOST=unix:///var/run/docker.sock
      - LOCALSTACK_HOST=localhost:4566
    volumes:
      - "${LOCALSTACK_VOLUME_DIR:-./volume}:/var/lib/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
```

#### 2. Start LocalStack

```bash
docker-compose up -d
```

#### 3. Configure Environment for LocalStack

```bash
# LocalStack endpoints
export AWS_ENDPOINT_URL_SECRETSMANAGER="http://localhost:4566"
export AWS_ENDPOINT_URL_MWAA="http://localhost:4566"

# AWS configuration (LocalStack accepts any values)
export AWS_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"

# Demo environment
export MWAA_ENVIRONMENT_NAME="demo-airflow-env"

# Last9 tracing
export OTEL_SERVICE_NAME="aws-local-demo"
export OTEL_EXPORTER_OTLP_ENDPOINT="YOUR_LAST9_ENDPOINT"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <YOUR_LAST9_BASIC_AUTH_TOKEN>"

# Server mode
export RUN_SERVER=true
export PORT=8080
```

#### 4. Run the Application

```bash
go run .
```

#### 5. Test the APIs

```bash
# Test Secrets Manager
curl -X POST http://localhost:8080/secrets/create \
  -H "Content-Type: application/json" \
  -d '{
    "secret_name": "test-api-key",
    "secret_value": "my-secret-123"
  }'

curl http://localhost:8080/secrets/test-api-key

# Test Airflow (will use mock since MWAA isn't fully supported in LocalStack)
curl -X POST http://localhost:8080/airflow/trigger \
  -H "Content-Type: application/json" \
  -d '{
    "dag_id": "sample_dag",
    "parameters": {"env": "test"}
  }'
```

### Option 2: Production Testing with Real AWS Services

#### 1. Set up AWS Credentials

```bash
# Service Account credentials
export AWS_ACCESS_KEY_ID="your-actual-access-key"
export AWS_SECRET_ACCESS_KEY="your-actual-secret-key"
export AWS_REGION="your-aws-region"

# Or use AWS CLI
aws configure
```

#### 2. Configure AWS Resources

```bash
export MWAA_ENVIRONMENT_NAME="your-actual-mwaa-environment"
```

#### 3. Run with Production Config

```bash
export RUN_SERVER=true
export OTEL_SERVICE_NAME="aws-production-demo"
go run .
```

## Observability Features

### OpenTelemetry Instrumentation

The application creates the following spans:

1. **HTTP Request Spans**: Auto-instrumented via middleware
2. **Secrets Manager Operations**:
   - `secretsmanager.secret.create` - Secret creation
   - `secretsmanager.secret.get` - Secret retrieval
3. **Airflow Operations**:
   - `airflow.dag.trigger` - DAG triggering

### Trace Attributes

- **Service identification**: `service.name`, `service.version`
- **HTTP details**: `http.request.method`, `http.response.status_code`
- **AWS resources**: `aws.request.id`, service names
- **Airflow details**: Environment name, DAG ID, execution parameters

### Error Handling

- Automatic error recording in spans
- Custom error messages for different failure scenarios
- Proper HTTP status code mapping
- AWS-specific error handling

## Viewing Traces in Last9

1. **Log into Last9**: https://app.last9.io
2. **Navigate to Traces**
3. **Filter by service**: Use your configured `OTEL_SERVICE_NAME` value
4. **Look for operations**:
   - `POST /secrets/create` - Secret creation requests
   - `GET /secrets/{name}` - Secret retrieval requests
   - `POST /airflow/trigger` - DAG trigger requests
   - `secretsmanager.secret.create` - Individual Secrets Manager calls
   - `airflow.dag.trigger` - Individual Airflow operations

## LocalStack Configuration Details

### Supported Services

- **Secrets Manager**: Full CRUD operations on secrets
- **MWAA**: Limited support (uses mock responses for DAG triggering)

### LocalStack Limitations

- MWAA API calls will use mock responses when LocalStack is detected
- Some advanced AWS features may not be available
- Billing and quotas are not enforced

### Debugging LocalStack

```bash
# Check LocalStack logs
docker logs localstack_aws

# List available services
curl http://localhost:4566/_localstack/health

# Test Secrets Manager directly
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets
```

## Environment Variables Reference

### Required for Last9
- `OTEL_SERVICE_NAME`: Service identifier in traces
- `OTEL_EXPORTER_OTLP_ENDPOINT`: Last9 OTLP endpoint
- `OTEL_EXPORTER_OTLP_HEADERS`: Last9 authentication header

### Required for AWS (Production)
- `AWS_REGION`: AWS region
- `AWS_ACCESS_KEY_ID`: AWS access key
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `MWAA_ENVIRONMENT_NAME`: Airflow environment name

### Required for LocalStack
- `AWS_ENDPOINT_URL_SECRETSMANAGER`: LocalStack Secrets Manager endpoint
- `AWS_ENDPOINT_URL_MWAA`: LocalStack MWAA endpoint

### Optional Configuration
- `RUN_SERVER`: Set to "true" for HTTP server mode
- `PORT`: HTTP server port (default: 8080)