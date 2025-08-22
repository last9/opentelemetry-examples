# Core PHP 8.2+ application Instrumentation with OpenTelemetry and Last9

This guide explains how to use OpenTelemetry with PHP 8.2+ to send traces to Last9. This guide is useful for PHP 8.2+ applications that are not using any framework.

## Prerequisites

- PHP 8.2+
- Composer
- OpenTelemetry PHP extension

## Installation

1. Install the OpenTelemetry PHP extension:

It is important to install the [PHP OpenTelemetry extension](https://github.com/open-telemetry/opentelemetry-php-instrumentation) before adding the required packages to your `composer.json` file. It enables the auto instrumentation of the PHP runtime.


```bash
pecl install opentelemetry
```

Add the extension to your `php.ini` file:
```ini
extension=opentelemetry.so
```

If using Docker, add to your Dockerfile:

```dockerfile
RUN install-php-extensions opentelemetry
```

Verify the extension is installed:
```bash
php -m | grep opentelemetry
```

Follow the [PHP OpenTelemetry extension](https://opentelemetry.io/docs/zero-code/php/#install-the-opentelemetry-extension) installation instructions to ensure the extension is correctly configured.

2. Add the required packages to your `composer.json`:

Mandatory packages:

```
open-telemetry/opentelemetry
open-telemetry/exporter-otlp
```

Optional packages:

```
open-telemetry/opentelemetry-auto-curl # if you are using the curl extension
open-telemetry/opentelemetry-auto-guzzle # if you are using the guzzlehttp/guzzle package
```

You can find additonal packages based on your framework in the [OpenTelemetry PHP](https://opentelemetry.io/docs/instrumentation/php/) documentation.

2. Install the packages:

```bash
composer install
```

## Usage

1. Copy the `src` directory to your project.
It includes following files for auto instrumentation of core PHP project and MySQLi instrumentation.

2. Initialize instrumentation in your entry point (index.php):

```php
<?php
require __DIR__ . '/vendor/autoload.php';
use \Last9\Instrumentation;

// Initialize instrumentation with your service name
$instrumentation = Instrumentation::init(getenv('OTEL_SERVICE_NAME'));

try {
    // Your application code here
    
    // Mark request as successful
    $instrumentation->setSuccess();
} catch (Exception $e) {
    // Record errors
    $instrumentation->setError($e);
    throw $e;
}
```

3. Set the following environment variables:

**Required variables:**
- `OTEL_EXPORTER_OTLP_ENDPOINT`: Your Last9 OpenTelemetry endpoint (must include `/v1/traces` path)
- `OTEL_EXPORTER_OTLP_HEADERS`: Authentication header for Last9
- `OTEL_SERVICE_NAME`: Your service name

**Optional variables:**
- `OTEL_PHP_AUTOLOAD_ENABLED`: Enable PHP auto-instrumentation (set to `true`)
- `OTEL_EXPORTER_OTLP_PROTOCOL`: Protocol to use for the exporter (set to `http/json`)
- `OTEL_PROPAGATORS`: Propagators to use (set to `baggage,tracecontext`)
- `OTEL_RESOURCE_ATTRIBUTES`: Resource attributes (set to `deployment.environment=production`)

**Example configuration:**
```bash
export OTEL_SERVICE_NAME="my-php-app"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io/v1/traces"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_BASE64_TOKEN"
export OTEL_PHP_AUTOLOAD_ENABLED="true"
export OTEL_EXPORTER_OTLP_PROTOCOL="http/json"
export OTEL_PROPAGATORS="baggage,tracecontext"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=production"
```

4. Run your application and see the traces in Last9 [Trace Explorer](https://app.last9.io/traces).

## Features

### Automatic Instrumentation

The following operations are automatically instrumented:

1. Database Operations (MySQL/MariaDB):
```php
$result = $mysqli->query("SELECT * FROM users");
$stmt = $mysqli->prepare("INSERT INTO users (name) VALUES (?)");
```

2. HTTP Client Operations:
```php
$client = new \GuzzleHttp\Client();
$response = $client->request('GET', 'https://api.example.com/data');
```

### Error Handling

The instrumentation automatically captures:
- Database errors (query failures, connection issues)
- HTTP client errors (timeouts, connection failures)
- PHP errors and exceptions
- HTTP status codes

Each error includes:
- Error message and code
- Stack trace
- Error context and attributes
- Error events in the span

## How It Works

The instrumentation:
1. Creates a root span for each incoming request with format `HTTP METHOD ENDPOINT`
2. Automatically instruments database and HTTP operations
3. Propagates context through the application
4. Handles error cases and status codes
5. Sends traces to Last9's OpenTelemetry endpoint

## Support

For issues or questions:
- Check [Last9 documentation](https://docs.last9.io)
- Contact Last9 support
- Review [OpenTelemetry PHP documentation](https://opentelemetry.io/docs/instrumentation/php/)
