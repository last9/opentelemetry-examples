# PHP 7.3 Manual Instrumentation with OpenTelemetry and Last9

This guide explains how to use Last9's OpenTelemetry traces endpoint to ingest PHP 7.3 application traces using OpenTelemetry.

## Note

This is a manual instrumentation implementation, as OpenTelemetry Auto-Instrumentation is not supported for PHP 7.3. The instrumentation will automatically capture:
- HTTP Requests
- Database Operations (MySQL/MariaDB)
- External HTTP Calls
- Errors and Exceptions

## Prerequisites

- PHP 7.3
- Composer
- Docker (optional)

## Directory Structure

```
your-project/
├── last9/
│   ├── instrumentation.php
│   ├── instrumentMySQLi.php
│   └── instrumentHttpClient.php
├── Dockerfile
├── docker-compose.yaml
├── composer.json
└── index.php
```

## Installation

1. Add the following to your `composer.json`:

```json
{
    "require": {
        "guzzlehttp/guzzle": "^7.0"
    }
}
```

2. If using Docker, create a `Dockerfile`:

```dockerfile
FROM php:7.3-apache

# Install dependencies and PHP extensions
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    default-mysql-client \
    && docker-php-ext-install zip pdo pdo_mysql mysqli \
    && docker-php-ext-enable mysqli pdo_mysql

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set working directory
WORKDIR /var/www/html

# Copy composer files first
COPY composer.json ./

# Copy all application files
COPY . .

# Install dependencies
RUN composer install

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# Enable Apache rewrite module
RUN a2enmod rewrite
```

3. Create a `docker-compose.yaml`:

```yaml
version: '3'

services:
  app:
    build: .
    ports:
      - "8080:80"
    volumes:
      - .:/var/www/html
    environment:
      - OTEL_TRACES_EXPORTER=otlp
      - OTEL_EXPORTER_OTLP_ENDPOINT=https://last9-otlp-endpoint
      - OTEL_EXPORTER_OTLP_HEADERS=last9_otel_auth_header
      - OTEL_SERVICE_NAME=your-service-name
      - OTEL_DEPLOYMENT_ENVIRONMENT=production
      - OTEL_LOG_LEVEL=debug
      - OTEL_EXPORTER_OTLP_HEADERS=Basic your-auth-header
      - DB_HOST=db
      - DB_USER=dbuser
      - DB_PASSWORD=dbpass
      - DB_NAME=dbname
    depends_on:
      - db

  db:
    image: mariadb:10.5
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: dbname
      MYSQL_USER: dbuser
      MYSQL_PASSWORD: dbpass
    volumes:
      - db_data:/var/lib/mysql
    ports:
      - "3306:3306"

volumes:
  db_data:
```

## Usage

1. Update your entrypoint file (example `index.php`):

```php
<?php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/last9/instrumentation.php';

// Create mysqli connection - automatically instrumented
$mysqli = new mysqli(
    getenv('DB_HOST'),
    getenv('DB_USER'),
    getenv('DB_PASSWORD'),
    getenv('DB_NAME')
);

// Create Last9 HTTP client - automatically instrumented
$http = new \Last9\InstrumentedHttpClient([
    'timeout' => 5,
    'connect_timeout' => 2
]);

// Your application code here
```

2. All of the following operations will be automatically instrumented:

Database queries:
```php
$result = $mysqli->query("SELECT * FROM users");
```

Prepared statements:
```php
$stmt = $mysqli->prepare("INSERT INTO users (name) VALUES (?)");
$stmt->bind_param("s", $name);
$stmt->execute();
```

HTTP calls:
```php
$response = $http->request('GET', 'https://api.example.com/data');
```

3. Start the application:

```bash
# If using Docker
docker-compose up --build

# If not using Docker
composer install
php -S localhost:8080
```

## Trace Context Propagation

The instrumentation automatically handles trace context propagation. When receiving requests from instrumented clients (like a Next.js frontend), it will:
1. Extract the trace context from the `traceparent` header
2. Use the extracted trace ID and parent span ID to connect the traces
3. Automatically propagate the context to database and HTTP client calls

## Error Handling

The instrumentation automatically captures:
- Database errors (query failures, connection issues)
- HTTP client errors (timeouts, connection failures)
- PHP errors and exceptions
- HTTP status codes (4xx, 5xx)

Each error is captured with:
- Error message and code
- Stack trace (when available)
- Error context and attributes
- Error events in the span

## Features

### Span Events
Errors are captured as span events with detailed information:

```json
{
    "name": "exception",
    "timeUnixNano": "timestamp",
    "attributes": {
        "exception.type": "MySQLError",
        "exception.message": "Error message",
        "exception.code": 1064,
        "exception.stacktrace": "Stack trace..."
    }
}
```

### Automatic Error Detection
The instrumentation automatically detects and tracks:
- SQL syntax errors
- Connection failures
- Timeout errors
- HTTP status codes
- PHP runtime errors

### Span Attributes
Each span includes relevant attributes:
- Database operations:
  - `db.system`: Database type
  - `db.statement`: SQL query
  - `db.operation`: Operation type (query/prepare/execute)
- HTTP operations:
  - `http.method`: HTTP method
  - `http.url`: Request URL
  - `http.status_code`: Response status
  - `http.response.body.size`: Response size

## Environment Variables

Required environment variables:
- `OTEL_EXPORTER_OTLP_ENDPOINT`: Your Last9 OpenTelemetry endpoint
- `OTEL_EXPORTER_OTLP_HEADERS`: Authentication header for Last9
- `OTEL_SERVICE_NAME`: Your service name
- `DB_HOST`: Database host
- `DB_USER`: Database user
- `DB_PASSWORD`: Database password
- `DB_NAME`: Database name

Optional environment variables:
- `OTEL_DEPLOYMENT_ENVIRONMENT`: Deployment environment (default: production)
- `OTEL_LOG_LEVEL`: Log level for OpenTelemetry (default: debug)

## Troubleshooting

Common issues and solutions:

1. Missing spans:
   - Check if mysqli extension is enabled
   - Verify environment variables are set
   - Check error logs for trace sending failures

2. Trace context not propagating:
   - Verify `traceparent` header format
   - Check if frontend is properly instrumented

3. Database connection issues:
   - Verify database credentials
   - Check network connectivity
   - Ensure database service is running

4. Error events not appearing:
   - Check log level settings
   - Verify error handling configuration
   - Check span formatting in payload

For more detailed debugging, enable debug logging:
```bash
docker-compose logs app
```

## Support

For issues or questions:
- Check [Last9 documentation](https://docs.last9.io)
- Contact Last9 support
- Review [OpenTelemetry PHP documentation](https://opentelemetry.io/docs/instrumentation/php/)