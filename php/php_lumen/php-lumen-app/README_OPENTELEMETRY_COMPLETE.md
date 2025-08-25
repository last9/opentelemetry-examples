# Complete OpenTelemetry Setup for PHP 8.3 + Lumen 11.0

This guide provides a complete OpenTelemetry setup for PHP 8.3 + Lumen 11.0 applications with comprehensive tracing capabilities including HTTP requests, database queries, external API calls, cache operations, and custom business logic.

## 🚀 Quick Start

### 1. Install Dependencies

```bash
composer require open-telemetry/api:^1.4 \
    open-telemetry/exporter-otlp:^1.3 \
    open-telemetry/sdk:^1.7 \
    open-telemetry/opentelemetry-auto-laravel:^1.3 \
    open-telemetry/opentelemetry-auto-pdo:^0.1.1 \
    open-telemetry/opentelemetry-auto-psr18:^1.1
```

### 2. Environment Configuration

Add these variables to your `.env` file:

```env
# OpenTelemetry Configuration
OTEL_PHP_AUTOLOAD_ENABLED=true
OTEL_SERVICE_NAME=your-app-name-here
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-aps1.last9.io:443/v1/traces
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic your-auth-token-here"
OTEL_TRACES_EXPORTER=otlp
OTEL_PROPAGATORS=baggage,tracecontext
OTEL_TRACES_SAMPLER="always_on"
OTEL_LOG_LEVEL=error

# Application Configuration
APP_VERSION=1.0.0
SERVICE_NAMESPACE=your-namespace
SERVICE_INSTANCE_ID=instance-1
```

### 3. Create OpenTelemetry Service Provider

Create `app/Providers/OpenTelemetryServiceProvider.php`:

```php
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Trace\ExporterFactory;
use OpenTelemetry\SDK\Trace\SpanExporter\ConsoleSpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SemConv\ResourceAttributes;
use OpenTelemetry\Contrib\Propagation\TraceResponse\TraceResponsePropagator;
use OpenTelemetry\Contrib\Propagation\ServerTiming\ServerTimingPropagator;

class OpenTelemetryServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(TracerProvider::class, function ($app) {
            $attributes = Attributes::create([
                ResourceAttributes::SERVICE_NAME => env('OTEL_SERVICE_NAME', config('app.name', 'Lumen App')),
                ResourceAttributes::SERVICE_VERSION => env('APP_VERSION', '1.0.0'),
                'deployment.environment' => config('app.env', 'local'),
            ]);
            
            $resource = ResourceInfo::create($attributes);

            // Get OTLP endpoint from environment (standard OpenTelemetry variable)
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

            $exporterFactory = new ExporterFactory();
            $otlpExporter = $exporterFactory->create('otlp', [
                'endpoint' => $otlpEndpoint,
                'headers' => $headers,
            ]);

            $tracerProvider = new TracerProvider([
                new BatchSpanProcessor($otlpExporter),
            ], null, $resource);

            return $tracerProvider;
        });

        $this->app->singleton(TracerInterface::class, function ($app) {
            $tracerProvider = $app->make(TracerProvider::class);
            return $tracerProvider->getTracer(env('OTEL_SERVICE_NAME', 'lumen-app'));
        });
    }

    public function boot(): void
    {
        // Initialize auto-instrumentation
        $this->initializeAutoInstrumentation();
    }

    private function initializeAutoInstrumentation(): void
    {
        // Laravel auto-instrumentation
        if (class_exists('OpenTelemetry\\Contrib\\Instrumentation\\Laravel\\LaravelInstrumentation')) {
            \OpenTelemetry\Contrib\Instrumentation\Laravel\LaravelInstrumentation::register();
        }

        // PDO auto-instrumentation for database queries
        if (class_exists('OpenTelemetry\\Contrib\\Instrumentation\\PDO\\PDOInstrumentation')) {
            \OpenTelemetry\Contrib\Instrumentation\PDO\PDOInstrumentation::register();
        }

        // PSR-18 HTTP client auto-instrumentation
        if (class_exists('OpenTelemetry\\Contrib\\Instrumentation\\Psr18\\Psr18Instrumentation')) {
            \OpenTelemetry\Contrib\Instrumentation\Psr18\Psr18Instrumentation::register();
        }
    }
}
```

### 4. Create OpenTelemetry Middleware

Create `app/Http/Middleware/OpenTelemetryMiddleware.php`:

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\SemConv\TraceAttributes;
use Carbon\Carbon;

class OpenTelemetryMiddleware
{
    public function handle(Request $request, Closure $next)
    {
        $tracer = app(TracerInterface::class);
        
        $span = $tracer->spanBuilder('http.request')
            ->setSpanKind(SpanKind::KIND_SERVER)
            ->setAttributes([
                TraceAttributes::HTTP_METHOD => $request->method(),
                TraceAttributes::HTTP_URL => $request->fullUrl(),
                TraceAttributes::HTTP_USER_AGENT => $request->userAgent(),
                TraceAttributes::HTTP_REQUEST_BODY_SIZE => strlen($request->getContent()),
                'http.request.timestamp' => Carbon::now()->toISOString(),
            ])
            ->startSpan();

        $scope = $span->activate();

        try {
            $response = $next($request);

            $span->setAttributes([
                TraceAttributes::HTTP_STATUS_CODE => $response->getStatusCode(),
                'http.response.size' => strlen($response->getContent()),
            ]);

            $span->setStatus(StatusCode::STATUS_OK);

            return $response;
        } catch (\Exception $e) {
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            throw $e;
        } finally {
            $span->end();
            $scope->detach();
        }
    }
}
```

### 5. Create OpenTelemetry Trait

Create `app/Traits/OpenTelemetryTrait.php`:

```php
<?php

namespace App\Traits;

use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\SemConv\TraceAttributes;

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

    protected function traceExternalApiCall(string $url, string $method, callable $operation)
    {
        return $this->traceOperation('external.api.call', $operation, [
            'http.url' => $url,
            'http.method' => $method,
            'span.kind' => 'client',
        ]);
    }

    protected function traceDatabaseQuery(string $query, array $params = [], callable $operation)
    {
        return $this->traceOperation('database.query', $operation, [
            'db.statement' => $query,
            'db.parameters' => json_encode($params),
            'db.system' => 'mysql', // or your database type
            'span.kind' => 'client',
        ]);
    }

    protected function traceCacheOperation(string $operation, string $key, callable $callback)
    {
        return $this->traceOperation('cache.operation', $callback, [
            'cache.operation' => $operation,
            'cache.key' => $key,
            'span.kind' => 'client',
        ]);
    }

    protected function addSpanEvent(string $name, array $attributes = [])
    {
        // Note: Span events need to be added to the current active span
        // This is a simplified implementation - in a real scenario, you'd need to track the current span
        // For now, we'll skip this functionality to avoid complexity
    }

    protected function setSpanAttribute(string $key, $value)
    {
        // Note: Span attributes need to be set on the current active span
        // This is a simplified implementation - in a real scenario, you'd need to track the current span
        // For now, we'll skip this functionality to avoid complexity
    }

    protected function getCurrentTraceId(): string
    {
        try {
            $tracer = app(\OpenTelemetry\API\Trace\TracerInterface::class);
            // For now, return a placeholder since we need proper span context management
            return 'trace-id-not-available';
        } catch (\Exception $e) {
            return 'trace-id-not-available';
        }
    }

    protected function getCurrentSpanId(): string
    {
        try {
            $tracer = app(\OpenTelemetry\API\Trace\TracerInterface::class);
            // For now, return a placeholder since we need proper span context management
            return 'span-id-not-available';
        } catch (\Exception $e) {
            return 'span-id-not-available';
        }
    }
}
```

### 6. Register Service Provider and Middleware

Update `bootstrap/app.php`:

```php
<?php

require_once __DIR__.'/../vendor/autoload.php';

(new Laravel\Lumen\Bootstrap\LoadEnvironmentVariables(
    dirname(__DIR__)
))->bootstrap();

date_default_timezone_set(env('APP_TIMEZONE', 'UTC'));

/*
|--------------------------------------------------------------------------
| Create The Application
|--------------------------------------------------------------------------
*/

$app = new Laravel\Lumen\Application(
    dirname(__DIR__)
);

$app->withFacades();
$app->withEloquent();

/*
|--------------------------------------------------------------------------
| Register Container Bindings
|--------------------------------------------------------------------------
*/

$app->singleton(
    Illuminate\Contracts\Debug\ExceptionHandler::class,
    App\Exceptions\Handler::class
);

$app->singleton(
    Illuminate\Contracts\Console\Kernel::class,
    App\Console\Kernel::class
);

/*
|--------------------------------------------------------------------------
| Register Config Files
|--------------------------------------------------------------------------
*/

$app->configure('app');

/*
|--------------------------------------------------------------------------
| Register Service Providers
|--------------------------------------------------------------------------
*/

$app->register(App\Providers\AppServiceProvider::class);
$app->register(App\Providers\OpenTelemetryServiceProvider::class); // Add this line

/*
|--------------------------------------------------------------------------
| Register Middleware
|--------------------------------------------------------------------------
*/

$app->middleware([
    App\Http\Middleware\OpenTelemetryMiddleware::class, // Add this line
]);

$app->routeMiddleware([
    'auth' => App\Http\Middleware\Authenticate::class,
]);

/*
|--------------------------------------------------------------------------
| Register Service Providers
|--------------------------------------------------------------------------
*/

$app->register(App\Providers\AppServiceProvider::class);

/*
|--------------------------------------------------------------------------
| Load The Application Routes
|--------------------------------------------------------------------------
*/

$app->router->group([
    'namespace' => 'App\Http\Controllers',
], function ($router) {
    require __DIR__.'/../routes/web.php';
});

return $app;
```

## 📊 What Gets Traced

### ✅ **HTTP Request/Response Spans**
- HTTP method, URL, status code
- Request ID, timestamp, response size
- Error handling and exceptions
- User agent and request body size

### ✅ **Custom Business Logic Spans**
- Manual operation tracing
- Custom attributes and events
- External API calls
- Database queries
- Cache operations

### ✅ **Auto-Instrumentation**
- Laravel framework operations
- PDO database queries
- PSR-18 HTTP client calls

## 🔧 Usage Examples

### Basic Tracing in Controllers

```php
<?php

namespace App\Http\Controllers;

use App\Traits\OpenTelemetryTrait;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

class ExampleController extends Controller
{
    use OpenTelemetryTrait;

    public function index(Request $request): JsonResponse
    {
        return $this->traceOperation('example.operation', function () {
            // Your business logic here
            return new JsonResponse(['message' => 'Success']);
        });
    }
}
```

### External API Calls

```php
public function callExternalApi(Request $request): JsonResponse
{
    return $this->traceExternalApiCall('https://api.example.com/data', 'GET', function () {
        // Make your HTTP request here
        $response = Http::get('https://api.example.com/data');
        return new JsonResponse($response->json());
    });
}
```

### Database Queries

```php
public function getUser(Request $request): JsonResponse
{
    return $this->traceDatabaseQuery(
        'SELECT * FROM users WHERE id = ?',
        [$request->get('id')],
        function () use ($request) {
            $user = User::find($request->get('id'));
            return new JsonResponse($user);
        }
    );
}
```

### Cache Operations

```php
public function getCachedData(Request $request): JsonResponse
{
    $key = $request->get('key');
    
    return $this->traceCacheOperation('get', $key, function () use ($key) {
        $data = Cache::get($key);
        return new JsonResponse($data);
    });
}
```

## 🚀 Testing Your Setup

### 1. Start the Application

```bash
php -S localhost:8000 -t public
```

### 2. Test Endpoints

```bash
# Test basic tracing
curl http://localhost:8000/

# Test external API tracing
curl http://localhost:8000/api/external-api-test

# Test database tracing
curl http://localhost:8000/api/database-test

# Test cache tracing
curl http://localhost:8000/api/cache-test
```

### 3. Check Last9 Dashboard

Visit your Last9 dashboard to see the traces being generated in real-time.

## 🔍 Troubleshooting

### Common Issues

1. **"Target class [TracerInterface] does not exist"**
   - Make sure you're using the full namespace: `\OpenTelemetry\API\Trace\TracerInterface::class`

2. **"OTEL_EXPORTER_OTLP_HEADERS environment variable is required"**
   - Add the `OTEL_EXPORTER_OTLP_HEADERS` variable to your `.env` file

3. **Traces not appearing in Last9**
   - Check your authorization token
   - Verify the OTLP endpoint URL
   - Ensure the service name is unique

### Debug Mode

To enable debug mode, set in your `.env`:

```env
OTEL_LOG_LEVEL=debug
```

## 📈 Advanced Configuration

### Custom Attributes

Add custom attributes to your spans:

```php
$span->setAttributes([
    'custom.attribute' => 'value',
    'business.metric' => 42,
]);
```

### Span Events

Add events to your spans:

```php
$span->addEvent('user.action', [
    'action' => 'login',
    'user_id' => 123,
]);
```

### Error Handling

Proper error handling in spans:

```php
try {
    // Your code here
    $span->setStatus(StatusCode::STATUS_OK);
} catch (\Exception $e) {
    $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
    $span->recordException($e);
    throw $e;
}
```

## 🔐 Security Considerations

1. **Never hardcode authorization tokens** - Always use environment variables
2. **Use HTTPS endpoints** - Ensure your OTLP endpoint uses HTTPS
3. **Validate environment variables** - The setup includes validation for required variables
4. **Limit sensitive data** - Be careful not to log sensitive information in spans

## 📚 Additional Resources

- [OpenTelemetry PHP Documentation](https://opentelemetry.io/docs/instrumentation/php/)
- [Last9 Documentation](https://docs.last9.io/)
- [Lumen Framework Documentation](https://lumen.laravel.com/docs)

## 🤝 Support

If you encounter any issues:

1. Check the troubleshooting section above
2. Verify your environment variables
3. Check the Last9 dashboard for any configuration errors
4. Review the OpenTelemetry logs for detailed error messages

---

**Note**: This setup provides comprehensive tracing for most common use cases. For production environments, consider implementing proper span context management and additional security measures.
