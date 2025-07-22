# Winston OpenTelemetry Logging Example

This example demonstrates how to integrate Winston logging with OpenTelemetry for centralized log management. It uses Winston as the logging framework and exports logs to Last9.

**OpenTelemetry package versions used in this example:**

- @opentelemetry/api: 1.9.0
- @opentelemetry/auto-instrumentations-node: 0.59.0
- @opentelemetry/exporter-trace-otlp-grpc: 0.201.1
- @opentelemetry/exporter-trace-otlp-http: 0.201.1
- @opentelemetry/instrumentation: 0.201.1
- @opentelemetry/resources: 2.0.1
- @opentelemetry/sdk-node: 0.201.1
- @opentelemetry/sdk-trace-base: 2.0.1
- @opentelemetry/sdk-trace-node: 2.0.1
- @opentelemetry/semantic-conventions: 1.34.0
- @opentelemetry/sdk-logs: 0.201.1
- @opentelemetry/api-logs: 0.201.1
- @opentelemetry/winston-transport: 0.11.0

**To install these exact OpenTelemetry dependencies:**

```bash
npm install \
  @opentelemetry/api@1.9.0 \
  @opentelemetry/auto-instrumentations-node@0.59.0 \
  @opentelemetry/exporter-trace-otlp-grpc@0.201.1 \
  @opentelemetry/exporter-trace-otlp-http@0.201.1 \
  @opentelemetry/instrumentation@0.201.1 \
  @opentelemetry/resources@2.0.1 \
  @opentelemetry/sdk-node@0.201.1 \
  @opentelemetry/sdk-trace-base@2.0.1 \
  @opentelemetry/sdk-trace-node@2.0.1 \
  @opentelemetry/semantic-conventions@1.34.0 \
  @opentelemetry/sdk-logs@0.201.1 \
  @opentelemetry/winston-transport@0.11.0 \
  @opentelemetry/api-logs@0.201.1
```

## Features

- Winston logging with multiple transports (Console, File, OpenTelemetry)
- OpenTelemetry log export integration
- Structured JSON logging
- Environment-based configuration
- Morgan HTTP request logging integration

## Prerequisites

- Node.js 14 or later
- An account with Last9

## Project Structure

```
.
├── src/
│   ├── config/
│   │   └── logger.js         # Winston logger configuration with OpenTelemetry
│   ├── routes/
│   │   └── users.routes.js   # Example API routes
│   └── server.js             # Express server setup
├── logs/                     # Local log files
├── .env.example              # Example environment variables
├── package.json
└── README.md
```

## Configuration

1. Copy `.env.example` to `.env` and update the values:

```bash
# Service name for OpenTelemetry
OTEL_SERVICE_NAME=your-service-name

# OpenTelemetry endpoint
OTEL_EXPORTER_OTLP_ENDPOINT=<last9_logs_otlp_endppoint>

# Optional: OpenTelemetry headers (e.g., for authentication)
OTEL_EXPORTER_OTLP_HEADERS=Authorization=<last9_auth_header>

# Log level (debug, info, warn, error)
LOG_LEVEL=info

# Server port
PORT=3000
```

## Installation

1. Install dependencies:
```bash
npm install
```

2. Start the server:
```bash
npm dev run
```

## Logging Features

### Winston Configuration

The logger is configured with:
- Console output
- OpenTelemetry log export to Last9
- JSON formatting for structured logs
- Timestamp and error stack trace inclusion

### Log Levels

Available log levels:
- error
- warn
- info
- debug

### Example Usage

```javascript
const logger = require('./config/logger');

// Basic logging
logger.info('User logged in', { userId: 123 });
logger.error('Failed to process request', { error: err });

// HTTP request logging (via Morgan)
app.use(morgan('combined', { stream: logger.stream }));
```

## OpenTelemetry Integration

The example uses:
- `@opentelemetry/exporter-logs-otlp-http` for log export
- `@opentelemetry/winston-transport` for Winston integration
- Resource attributes for service identification

Refer to `config/logger.js` for details of setting up Winston logger with OpenTelemetry.