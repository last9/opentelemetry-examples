# Node 14 Express with OpenTelemetry + Last9

Complete example of integrating OpenTelemetry with a Node.js 14 Express application, sending traces to Last9.

## ⚠️ Important Notes

- **Node 14 reached EOL on April 30, 2023** - This example is for legacy application support
- If possible, upgrade to Node 18 LTS or Node 20 LTS for better security and OTel 2.x support
- OpenTelemetry SDK 2.x dropped Node 14 support - this example uses SDK 1.x (0.52.1)

## Prerequisites

- Node.js 14.x (use nvm to manage versions)
- npm 6.x or higher
- Last9 account with OTLP endpoint credentials
- Docker (optional, for containerized testing)

## Quick Start with nvm

### 1. Install and Use Node 14

```bash
# Install Node 14 if not already installed
nvm install 14

# Switch to Node 14
nvm use 14

# Verify version
node --version  # Should show v14.x.x
```

### 2. Install Dependencies

```bash
cd node14-express
npm install
```

### 3. Configure Last9 Credentials

Copy the example environment file and add your Last9 credentials:

```bash
cp .env.example .env
```

Edit `.env` and replace `YOUR_LAST9_TOKEN_HERE` with your actual Last9 token:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://<your-last9-endpoint>
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <your-base64-token>
OTEL_SERVICE_NAME=node14-express-example
```

### 4. Run the Application

```bash
# Load environment variables and start
source .env
npm start
```

The server will start on `http://localhost:3000`.

### 5. Generate Test Traffic

```bash
# Make the test script executable (first time only)
chmod +x test-traces.sh

# Run tests
./test-traces.sh
```

## Quick Start with Docker

### 1. Set Environment Variables

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://<your-last9-endpoint>
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"
export OTEL_SERVICE_NAME=node14-express-example
```

### 2. Run with Docker Compose

```bash
docker-compose up --build
```

### 3. Test the Application

```bash
./test-traces.sh http://localhost:3000
```

## Test Endpoints

The application includes 7 endpoints demonstrating various OpenTelemetry features:

| Endpoint | Purpose | Demo Feature |
|----------|---------|--------------|
| `GET /health` | Health check | Basic tracing |
| `GET /` | Hello world | Simple span |
| `GET /custom-span` | Business logic | Custom span creation |
| `GET /external-call` | API call | HTTP client instrumentation |
| `GET /users/:id` | User lookup | Nested spans |
| `GET /slow?delay=ms` | Slow response | Performance monitoring |
| `GET /error` | Error trigger | Error tracking |

Each response includes a `traceId` field for correlation with Last9 traces.

## Verify in Last9

1. Navigate to your Last9 dashboard
2. Go to the Traces section
3. Filter by service name: `node14-express-example`
4. You should see traces for all test endpoints with:
   - HTTP method, path, status code
   - Response times
   - Custom attributes
   - Nested spans (for `/users/:id`)
   - Error tracking (for `/error`)

## Package Versions Explained

This example uses **OpenTelemetry SDK 1.x** versions for Node 14 compatibility:

```json
{
  "@opentelemetry/api": "1.9.0",              // Stable API
  "@opentelemetry/sdk-node": "0.52.1",        // Last SDK 1.x version
  "@opentelemetry/auto-instrumentations-node": "0.49.1",
  "@opentelemetry/exporter-trace-otlp-http": "0.52.1"
}
```

**Why these versions?**
- OpenTelemetry SDK 2.0+ requires Node 18.19.0+ (dropped Node 14/16 support)
- SDK 1.x (0.x.x experimental) is the last to support Node 14
- Version 0.52.1 is stable and well-tested

## Project Structure

```
node14-express/
├── app.js                      # Express application with test endpoints
├── instrumentation.js          # OpenTelemetry SDK initialization (with sampling)
├── package.json                # Dependencies (OTel SDK 1.x)
├── .npmrc                      # Prevent parent package interference
├── .env.example                # Environment configuration template
├── Dockerfile                  # Node 14 alpine container
├── docker-compose.yml          # Container orchestration (supports collector profile)
├── otel-collector-config.yaml  # Tail-based sampling configuration
├── test-traces.sh              # Automated testing script
├── deployments/                # Deployment-specific configurations
│   ├── pm2/                    # PM2 + Docker collector
│   ├── kubernetes/             # K8s manifests
│   ├── docker/                 # Docker Compose examples
│   └── standalone/             # Systemd service setup
└── README.md                   # This file
```

## Sampling Configuration

This example supports two sampling strategies, depending on your needs:

| Aspect | Head-Based (SDK) | Tail-Based (Collector) |
|--------|------------------|------------------------|
| **Location** | instrumentation.js | OTel Collector |
| **Decision timing** | At span creation | After trace completes |
| **Can filter errors?** | No | Yes (100% of errors kept) |
| **Can filter slow traces?** | No | Yes (configurable threshold) |
| **Infrastructure** | None extra | Requires Collector |
| **Memory overhead** | Minimal | Higher (holds traces) |

### Option 1: Head-Based Sampling (SDK)

Configure via environment variables - no infrastructure changes needed:

```bash
# Sample 10% of traces
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

**Available samplers:**

| Sampler | Description |
|---------|-------------|
| `always_on` | Sample 100% of traces |
| `always_off` | Sample 0% of traces |
| `traceidratio` | Sample based on trace ID (configurable ratio) |
| `parentbased_traceidratio` | Inherit parent decision, or use ratio for root spans |
| `parentbased_always_on` | Inherit parent decision, always sample root spans |
| `parentbased_always_off` | Inherit parent decision, never sample root spans |

**Run with head-based sampling:**
```bash
export OTEL_TRACES_SAMPLER=parentbased_traceidratio
export OTEL_TRACES_SAMPLER_ARG=0.1
npm start
```

### Option 2: Tail-Based Sampling (Collector)

Uses the OTel Collector to make intelligent sampling decisions after traces complete. This keeps:
- 100% of traces with errors
- 100% of slow traces (>2s latency)
- 10% of remaining normal traces

**Run with tail-based sampling:**
```bash
# Set collector credentials
export LAST9_OTLP_ENDPOINT=https://<your-last9-endpoint>
export LAST9_AUTH_HEADER="Basic <your-token>"

# Start with collector profile
docker-compose --profile with-collector up
```

**Customize sampling policies** in `otel-collector-config.yaml`:
```yaml
tail_sampling:
  policies:
    - name: always_sample_errors
      type: status_code
      status_code:
        status_codes: [ERROR]
    - name: always_sample_slow
      type: latency
      latency:
        threshold_ms: 2000  # Adjust threshold as needed
    - name: probabilistic_fallback
      type: probabilistic
      probabilistic:
        sampling_percentage: 10  # Adjust percentage as needed
```

**Key settings:**
- `decision_wait`: Time to wait for all spans (default: 10s)
- `num_traces`: Max traces held in memory (default: 100)
- Collector image must be `contrib` variant (has tail_sampling processor)

### Deployment-Specific Examples

See [`deployments/`](./deployments/) for complete configurations:

| Environment | Directory | Description |
|-------------|-----------|-------------|
| **PM2** | `deployments/pm2/` | ecosystem.config.js + collector setup script |
| **Kubernetes** | `deployments/kubernetes/` | Deployment, Service, RBAC, ConfigMap |
| **Docker** | `deployments/docker/` | docker-compose with collector |
| **Standalone** | `deployments/standalone/` | systemd service installation |

## Key Implementation Details

### Auto-Instrumentation

This example uses `@opentelemetry/auto-instrumentations-node` which automatically instruments:
- HTTP/HTTPS (client and server)
- Express framework
- Database clients (pg, mysql, mongodb, etc.)
- Redis, gRPC, DNS, and more

No code changes required for basic instrumentation!

### Custom Spans

See `/custom-span` endpoint in `app.js` for examples of:
- Creating custom spans with `tracer.startSpan()`
- Adding attributes with `span.setAttribute()`
- Recording exceptions with `span.recordException()`
- Setting span status

### Nested Spans

See `/users/:id` endpoint for parent-child span relationships:
```javascript
const parentSpan = tracer.startSpan('user.lookup');
const childSpan = tracer.startSpan('db.query', {},
  opentelemetry.trace.setSpan(context.active(), parentSpan)
);
```

## Troubleshooting

### "Cannot find module 'node:events'" Error

This means a dependency is using modern Node.js syntax. Solutions:
1. Ensure you're using Node 14.13.1+ (not earlier 14.x versions)
2. Check that `.npmrc` is present to prevent parent package interference
3. Delete `node_modules` and reinstall: `rm -rf node_modules && npm install`

### npm Uses Parent Package.json

If npm installs dependencies from `/Users/prathamesh2_/Projects/node_modules`:
1. Verify `.npmrc` exists in this directory
2. Delete any existing `node_modules` and `package-lock.json`
3. Run `npm install` again

### No Traces Appearing in Last9

1. Check environment variables are set correctly
2. Verify Last9 token is valid and base64 encoded
3. Check application logs for OTLP export errors
4. Ensure network connectivity to your Last9 OTLP endpoint
5. Test with `OTEL_LOG_LEVEL=debug` for verbose logging

### Docker Build Issues

If Docker build fails:
1. Ensure Docker has internet access
2. Try clearing Docker cache: `docker-compose build --no-cache`
3. Check if Node 14 alpine image is available: `docker pull node:14-alpine`

## Upgrade Path

When you're ready to upgrade from Node 14:

### To Node 18 LTS or Node 20 LTS

1. Update `package.json` engines:
   ```json
   "engines": {
     "node": ">=18.19.0"
   }
   ```

2. Update OpenTelemetry to 2.x:
   ```json
   {
     "@opentelemetry/api": "^1.9.0",
     "@opentelemetry/sdk-node": "^0.56.0",
     "@opentelemetry/auto-instrumentations-node": "^0.52.0",
     "@opentelemetry/exporter-trace-otlp-http": "^0.56.0"
   }
   ```

3. Update Dockerfile:
   ```dockerfile
   FROM node:20-alpine
   ```

4. Test thoroughly - OpenTelemetry 2.x has breaking changes

## Additional Resources

- [Last9 Documentation](https://docs.last9.io)
- [OpenTelemetry JavaScript SDK](https://opentelemetry.io/docs/languages/js/)
- [Node.js Release Schedule](https://nodejs.org/en/about/previous-releases)
- [OpenTelemetry Auto-Instrumentations](https://www.npmjs.com/package/@opentelemetry/auto-instrumentations-node)

## Support

For issues or questions:
- Last9 Support: [Last9 Support Portal]
- OpenTelemetry: [GitHub Discussions](https://github.com/open-telemetry/opentelemetry-js/discussions)

## License

This example is provided as-is for demonstration purposes.
