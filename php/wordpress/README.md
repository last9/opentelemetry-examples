# WordPress OpenTelemetry Integration with Last9

This example demonstrates how to instrument WordPress 6.8.3 with OpenTelemetry for automatic tracing, sending telemetry data directly to Last9.

## Overview

The setup uses **zero-code instrumentation** via the official OpenTelemetry WordPress auto-instrumentation package. No modifications to WordPress core or plugins are required.

### What Gets Instrumented

- WordPress request lifecycle (hooks, actions, filters)
- Database queries (MySQL/MariaDB via PDO)
- HTTP client requests (cURL-based plugins, REST API calls)
- WordPress hook execution timing

## Prerequisites

- Docker and Docker Compose
- Last9 account with OTLP endpoint credentials

## Quick Start

1. **Clone and configure:**

   ```bash
   cd php/wordpress
   cp .env.example .env
   # Edit .env with your Last9 credentials
   ```

2. **Start the stack:**

   ```bash
   docker compose up -d
   ```

3. **Access WordPress:**

   Open http://localhost:8080 and complete the WordPress installation wizard.

4. **View traces in Last9:**

   Navigate to your Last9 dashboard to see WordPress traces.

## Architecture

```
┌─────────────────┐     OTLP/HTTP     ┌──────────────────┐
│    WordPress    │ ───────────────── │   Last9 OTLP     │
│   (PHP 8.2)     │                   │    Endpoint      │
│                 │                   └──────────────────┘
│  ┌───────────┐  │
│  │  OTel     │  │
│  │  Auto-    │  │
│  │  Instrum. │  │
└──┴───────────┴──┘
```

## Configuration

### Environment Variables

Configure via `.env` file or environment variables:

```bash
# Required: Last9 OTLP endpoint
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io

# Required: Authorization header
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <your-credentials>

# Optional: Sampling (default: always_on)
OTEL_TRACES_SAMPLER=always_on

# Optional: Resource attributes
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.version=6.8.3

# Optional: Log level
OTEL_LOG_LEVEL=info
```

### All Available Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name in traces | `wordpress` |
| `OTEL_TRACES_EXPORTER` | Exporter type | `otlp` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint URL | `https://otlp.last9.io` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers | - |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Protocol (http/protobuf, http/json, grpc) | `http/protobuf` |
| `OTEL_TRACES_SAMPLER` | Sampling strategy | `always_on` |
| `OTEL_RESOURCE_ATTRIBUTES` | Additional resource attributes | - |
| `OTEL_PHP_AUTOLOAD_ENABLED` | Enable auto-instrumentation | `true` |
| `OTEL_LOG_LEVEL` | OTel SDK log level | `info` |

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Custom WordPress image with OTel extension and packages |
| `docker-compose.yaml` | Stack definition (WordPress + MariaDB) |
| `composer.json` | OTel PHP dependencies |
| `otel-bootstrap.php` | Auto-prepend file for OTel initialization |
| `.env.example` | Template for Last9 credentials |

## How It Works

1. **Dockerfile** installs the OpenTelemetry PHP extension and OTel packages via Composer
2. **otel-bootstrap.php** is auto-prepended before WordPress loads (via `auto_prepend_file`)
3. **Auto-instrumentation packages** hook into WordPress, PDO, and cURL automatically
4. **Environment variables** configure the OTLP exporter to send traces to Last9

## Customization

### Adding Custom Spans

If you need manual instrumentation in a custom plugin:

```php
use OpenTelemetry\API\Globals;

$tracer = Globals::tracerProvider()->getTracer('my-plugin');
$span = $tracer->spanBuilder('custom-operation')->startSpan();

try {
    // Your code here
    $span->setAttribute('custom.attribute', 'value');
} finally {
    $span->end();
}
```

### Instrumenting Additional Libraries

Add more auto-instrumentation packages in `composer.json`:

```json
{
    "require": {
        "open-telemetry/opentelemetry-auto-guzzle": "^1.0",
        "open-telemetry/opentelemetry-auto-psr18": "^1.0"
    }
}
```

Then rebuild: `docker compose build --no-cache`

## Troubleshooting

### Traces not appearing in Last9

1. Check OTel extension is loaded:
   ```bash
   docker compose exec wordpress php -m | grep opentelemetry
   ```

2. Verify environment variables:
   ```bash
   docker compose exec wordpress env | grep OTEL
   ```

3. Test OTLP endpoint connectivity:
   ```bash
   docker compose exec wordpress curl -s -o /dev/null -w "%{http_code}" \
     "${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces" -X POST \
     -H "Authorization: Basic <credentials>" \
     -H "Content-Type: application/x-protobuf"
   ```

### Performance Considerations

- The `protobuf` PHP extension is installed for optimal OTLP serialization
- Use `http/protobuf` protocol for best performance
- Adjust sampling for high-traffic sites:
  ```bash
  OTEL_TRACES_SAMPLER=parentbased_traceidratio
  OTEL_TRACES_SAMPLER_ARG=0.1  # Sample 10% of traces
  ```

## Cleanup

```bash
docker compose down -v
```

## Resources

- [OpenTelemetry PHP Documentation](https://opentelemetry.io/docs/languages/php/)
- [WordPress Auto-Instrumentation Package](https://packagist.org/packages/open-telemetry/opentelemetry-auto-wordpress)
- [Last9 Documentation](https://docs.last9.io/)
