# Laravel PHP 7.4 with OpenTelemetry Tracing

This project demonstrates how to add OpenTelemetry manual instrumentation to a Laravel PHP 7.4 application without requiring PHP extensions.

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose installed
- Git

### 1. Clone and Setup
```bash
git clone <repository-url>
cd <repository-name>
```

### 2. Start the Application
```bash
# Build and start all services
docker-compose up -d --build

# Wait for services to be ready (about 30 seconds)
sleep 30
```

### 3. Run Database Migrations
```bash
# Run migrations to create the users table
docker-compose exec laravel-app php artisan migrate

# Seed a test user
docker-compose exec laravel-app php artisan tinker --execute="\\App\\User::create(['name' => 'Test User', 'email' => 'test@example.com', 'password' => bcrypt('password')]);"
```

### 4. Test the Application
```bash
# Test basic endpoint
curl http://localhost:8000/

# Test Eloquent ORM tracing
curl http://localhost:8000/api/eloquent-example

# Test database operations
curl http://localhost:8000/api/database-example

# Test HTTP client tracing
curl http://localhost:8000/api/curl-example
curl http://localhost:8000/api/guzzle-example
```

### 5. View Traces
Open your browser and navigate to:
- **Jaeger UI**: http://localhost:16686
- **Laravel App**: http://localhost:8000

In Jaeger, look for service: `laravel-app`

## 📊 What Gets Traced

### ✅ Automatic HTTP Tracing
- All HTTP requests through Laravel middleware
- Standard OpenTelemetry attributes: `http.request.method`, `url.path`, `server.address`
- Response tracking: Status codes, response times, errors

### 🔄 Database Tracing
- **All database queries** (Eloquent ORM, Query Builder, raw SQL) via `DB::listen`
- **Eloquent model events** (retrieved, created, updated, deleted, saved, restored)
- OpenTelemetry database attributes: `db.system`, `db.statement`, `db.operation`
- Performance metrics: Query duration, rows affected

### 🌐 HTTP Client Tracing
- External API calls with curl and Guzzle
- OpenTelemetry HTTP client semantic conventions
- Distributed tracing with W3C `traceparent` headers

## 🔧 Configuration

### Environment Variables
The application uses these environment variables (configured in `docker-compose.yml`):

```bash
# Database
DB_HOST=mysql
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret

# OpenTelemetry
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318/v1/traces
OTEL_SERVICE_NAME=laravel-app
OTEL_SERVICE_VERSION=1.0.0
```

### Services
- **Laravel App**: http://localhost:8000 (PHP 7.4 + Laravel 7.x)
- **MySQL Database**: localhost:3306
- **OpenTelemetry Collector**: OTLP HTTP on port 4318
- **Jaeger UI**: http://localhost:16686

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Laravel App   │───▶│  OTEL Collector  │───▶│   Jaeger UI     │
│   (PHP 7.4)     │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│   MySQL DB      │
└─────────────────┘
```

## 🎯 Manual Instrumentation Features

### Database Query Tracing
All database queries are automatically traced via `DB::listen` in `AppServiceProvider`:

```php
\DB::listen(function ($query) {
    // Automatically traces all DB queries
    $GLOBALS['simple_tracer']->traceDatabase($sql, $connection, ...);
});
```

### Eloquent Model Event Tracing
Eloquent model events are traced via event listeners:

```php
\Event::listen([
    'eloquent.retrieved: *',
    'eloquent.created: *',
    // ... other events
], function ($eventName, $models) {
    // Traces Eloquent model operations
});
```

### HTTP Request Tracing
HTTP requests are traced via middleware (`OpenTelemetryMiddleware`).

## 🐛 Troubleshooting

### Common Issues

1. **Services not starting**
   ```bash
   docker-compose logs
   ```

2. **Database connection issues**
   ```bash
   docker-compose exec laravel-app php artisan migrate:status
   ```

3. **No traces appearing**
   - Check if the collector is running: `docker-compose ps`
   - Check collector logs: `docker-compose logs otel-collector`
   - Verify the endpoint URL in environment variables

4. **Permission issues**
   ```bash
   docker-compose exec laravel-app chown -R www-data:www-data /var/www/html/storage
   ```

### Debug Logs
Check the debug log for troubleshooting:
```bash
docker-compose exec laravel-app cat /tmp/debug.log
```

## 🧹 Cleanup
```bash
# Stop all services
docker-compose down

# Remove volumes (will delete database data)
docker-compose down -v

# Remove images
docker-compose down --rmi all
```

## 📚 Documentation

- [OpenTelemetry PHP](https://opentelemetry.io/docs/instrumentation/php/)
- [Laravel Documentation](https://laravel.com/docs/7.x)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)