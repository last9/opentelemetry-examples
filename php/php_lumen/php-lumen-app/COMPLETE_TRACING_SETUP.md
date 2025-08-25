# Complete OpenTelemetry Tracing Setup for PHP 8.3 + Lumen 11.0

## Current Setup Limitations

Your current setup only captures:
- ✅ HTTP request/response spans
- ✅ Custom business logic spans
- ❌ Database queries
- ❌ Third-party API calls
- ❌ Cache operations
- ❌ Queue jobs

## Enhanced Dependencies

Add these packages to your `composer.json`:

```json
{
    "require": {
        "open-telemetry/api": "^1.4",
        "open-telemetry/exporter-otlp": "^1.3",
        "open-telemetry/sdk": "^1.7",
        "open-telemetry/instrumentation-pdo": "^0.1.0",
        "open-telemetry/instrumentation-http": "^0.1.0",
        "open-telemetry/instrumentation-laravel": "^0.1.0",
        "open-telemetry/instrumentation-cache": "^0.1.0"
    }
}
```

## Enhanced OpenTelemetryServiceProvider

```php
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SemConv\ResourceAttributes;

class OpenTelemetryServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(TracerProvider::class, function ($app) {
            $attributes = Attributes::create([
                ResourceAttributes::SERVICE_NAME => env('OTEL_SERVICE_NAME', config('app.name', 'Lumen App')),
                ResourceAttributes::SERVICE_VERSION => env('APP_VERSION', '1.0.0'),
                'deployment.environment' => config('app.env', 'local'),
                'service.namespace' => env('SERVICE_NAMESPACE', 'default'),
                'service.instance.id' => env('SERVICE_INSTANCE_ID', uniqid()),
            ]);
            
            $resource = ResourceInfo::create($attributes);

            // Get OTLP endpoint from environment
            $otlpEndpoint = env('OTEL_EXPORTER_OTLP_ENDPOINT', env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'https://otlp-aps1.last9.io:443/v1/traces'));
            
            // Get authorization from environment
            $authHeader = env('OTEL_EXPORTER_OTLP_HEADERS');
            
            if (!$authHeader) {
                throw new \Exception('OTEL_EXPORTER_OTLP_HEADERS environment variable is required for OpenTelemetry configuration');
            }
            
            $authValue = str_replace('Authorization=', '', $authHeader);
            
            $headers = [
                'Authorization' => $authValue,
                'Content-Type' => 'application/json'
            ];
            
            $transport = (new OtlpHttpTransportFactory())->create(
                $otlpEndpoint,
                'application/json',
                $headers
            );
            
            $exporter = new SpanExporter($transport);
            $spanProcessor = new SimpleSpanProcessor($exporter);

            return new TracerProvider([$spanProcessor], null, $resource);
        });

        $this->app->singleton(TracerInterface::class, function ($app) {
            $tracerProvider = $app->make(TracerProvider::class);
            return $tracerProvider->getTracer(env('OTEL_SERVICE_NAME', 'lumen-app'));
        });
    }

    public function boot(): void
    {
        // Initialize instrumentations if available
        $this->initializeInstrumentations();
    }

    private function initializeInstrumentations(): void
    {
        // Database instrumentation
        if (class_exists('OpenTelemetry\Instrumentation\PDO\PDOInstrumentation')) {
            \OpenTelemetry\Instrumentation\PDO\PDOInstrumentation::register();
        }

        // HTTP client instrumentation
        if (class_exists('OpenTelemetry\Instrumentation\Http\HTTPInstrumentation')) {
            \OpenTelemetry\Instrumentation\Http\HTTPInstrumentation::register();
        }

        // Laravel instrumentation
        if (class_exists('OpenTelemetry\Instrumentation\Laravel\LaravelInstrumentation')) {
            \OpenTelemetry\Instrumentation\Laravel\LaravelInstrumentation::register();
        }

        // Cache instrumentation
        if (class_exists('OpenTelemetry\Instrumentation\Cache\CacheInstrumentation')) {
            \OpenTelemetry\Instrumentation\Cache\CacheInstrumentation::register();
        }
    }
}
```

## Enhanced Environment Variables

```env
# OpenTelemetry Configuration
OTEL_PHP_AUTOLOAD_ENABLED=true
OTEL_SERVICE_NAME=your-app-name
OTEL_TRACES_EXPORTER=otlp
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-aps1.last9.io:443/v1/traces
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic your-token-here"
OTEL_PROPAGATORS=baggage,tracecontext
OTEL_TRACES_SAMPLER="always_on"
OTEL_LOG_LEVEL=error

# Service Configuration
APP_VERSION=1.0.0
SERVICE_NAMESPACE=your-namespace
SERVICE_INSTANCE_ID=instance-1

# Database Tracing (if using PDO)
OTEL_INSTRUMENTATION_PDO_ENABLED=true

# HTTP Client Tracing
OTEL_INSTRUMENTATION_HTTP_ENABLED=true

# Laravel Instrumentation
OTEL_INSTRUMENTATION_LARAVEL_ENABLED=true
```

## Enhanced OpenTelemetryTrait

```php
<?php

namespace App\Traits;

use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;

trait OpenTelemetryTrait
{
    protected function traceOperation(string $operationName, callable $operation, array $attributes = [])
    {
        $tracer = app(TracerInterface::class);
        
        $span = $tracer->spanBuilder($operationName)
            ->setSpanKind(SpanKind::KIND_INTERNAL)
            ->setAttributes($attributes)
            ->startSpan();

        $scope = $span->activate();

        try {
            $result = $operation();
            $span->setStatus(StatusCode::STATUS_OK);
            return $result;
        } catch (\Exception $e) {
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            throw $e;
        } finally {
            $span->end();
            $scope->detach();
        }
    }

    protected function traceDatabaseQuery(string $query, array $params = [], callable $operation)
    {
        return $this->traceOperation('database.query', $operation, [
            'db.statement' => $query,
            'db.parameters' => json_encode($params),
            'db.system' => 'mysql', // or your database type
        ]);
    }

    protected function traceExternalApiCall(string $url, string $method, callable $operation)
    {
        return $this->traceOperation('external.api.call', $operation, [
            'http.url' => $url,
            'http.method' => $method,
            'span.kind' => 'client',
        ]);
    }

    protected function traceCacheOperation(string $operation, string $key, callable $cacheCall)
    {
        return $this->traceOperation('cache.operation', $cacheCall, [
            'cache.operation' => $operation,
            'cache.key' => $key,
        ]);
    }

    // ... existing methods ...
}
```

## Usage Examples

### Database Tracing
```php
public function getUser($id)
{
    return $this->traceDatabaseQuery(
        "SELECT * FROM users WHERE id = ?",
        [$id],
        function () use ($id) {
            return DB::table('users')->where('id', $id)->first();
        }
    );
}
```

### External API Tracing
```php
public function callExternalApi()
{
    return $this->traceExternalApiCall(
        'https://api.example.com/data',
        'GET',
        function () {
            return Http::get('https://api.example.com/data');
        }
    );
}
```

### Cache Tracing
```php
public function getCachedData($key)
{
    return $this->traceCacheOperation(
        'get',
        $key,
        function () use ($key) {
            return Cache::get($key);
        }
    );
}
```

## What This Enhanced Setup Captures:

✅ **HTTP Request/Response** - Complete request lifecycle
✅ **Database Queries** - SQL statements, parameters, execution time
✅ **External API Calls** - URLs, methods, response times
✅ **Cache Operations** - Cache hits/misses, operation types
✅ **Custom Business Logic** - Manual tracing with attributes
✅ **Error Tracking** - Exceptions, stack traces
✅ **Performance Metrics** - Response times, throughput
✅ **Service Dependencies** - Database, external APIs, caches

## Testing Complete Tracing

```bash
# Test HTTP request
curl http://localhost:8000/

# Test database operations (if you have a database endpoint)
curl http://localhost:8000/api/users

# Test external API calls
curl http://localhost:8000/api/external-data

# Test cache operations
curl http://localhost:8000/api/cache-test
```

This enhanced setup will give you complete visibility into your application's performance and dependencies.
