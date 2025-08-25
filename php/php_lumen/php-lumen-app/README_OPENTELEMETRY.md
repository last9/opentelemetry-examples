# OpenTelemetry Integration for Lumen 10.0

This document explains the OpenTelemetry tracing integration for your Lumen 10.0 application.

## 🎯 **Overview**

The application now includes OpenTelemetry tracing capabilities that automatically track:
- HTTP requests and responses
- Controller operations
- Custom spans and events
- Performance metrics
- Error tracking

## 📦 **Installed Packages**

- `open-telemetry/api` - Core OpenTelemetry API
- `open-telemetry/sdk` - OpenTelemetry SDK implementation

## 🏗️ **Architecture**

### Components

1. **OpenTelemetryServiceProvider** (`app/Providers/OpenTelemetryServiceProvider.php`)
   - Configures the TracerProvider
   - Sets up ConsoleSpanExporter (outputs to console)
   - Registers TracerInterface in the container

2. **OpenTelemetryMiddleware** (`app/Http/Middleware/OpenTelemetryMiddleware.php`)
   - Automatically traces all HTTP requests
   - Captures request/response metadata
   - Handles errors and exceptions

3. **OpenTelemetryTrait** (`app/Traits/OpenTelemetryTrait.php`)
   - Provides helper methods for controllers
   - Enables custom span creation
   - Simplifies tracing operations

## 🚀 **Usage**

### Automatic Tracing

All HTTP requests are automatically traced. The middleware captures:
- HTTP method and URL
- Request headers
- Response status code
- Response size
- Request timing
- Errors and exceptions

### Manual Tracing in Controllers

Use the `OpenTelemetryTrait` in your controllers:

```php
use App\Traits\OpenTelemetryTrait;

class YourController extends Controller
{
    use OpenTelemetryTrait;

    public function someMethod()
    {
        return $this->traceOperation('operation.name', function () {
            // Your code here
            return response()->json(['data' => 'result']);
        }, [
            'custom_attribute' => 'value'
        ]);
    }
}
```

### Adding Custom Events

```php
$this->addSpanEvent('user.login', [
    'user_id' => $userId,
    'login_method' => 'email'
]);
```

### Setting Custom Attributes

```php
$this->setSpanAttribute('database.query_count', 5);
$this->setSpanAttribute('cache.hit_ratio', 0.85);
```

## 🧪 **Testing the Integration**

### Test Endpoints

1. **Basic Info Endpoint** (with tracing):
   ```bash
   curl http://localhost:8000/api/info
   ```

2. **Trace Test Endpoint**:
   ```bash
   curl http://localhost:8000/api/trace-test
   ```

3. **Any Other Endpoint** (all are traced):
   ```bash
   curl http://localhost:8000/health
   curl http://localhost:8000/test
   ```

### Viewing Traces

Currently, traces are exported to the console. You'll see output like:

```
SpanData {
  name: "http.request"
  traceId: "1234567890abcdef1234567890abcdef"
  spanId: "1234567890abcdef"
  parentSpanId: ""
  startTime: 2024-01-01T12:00:00.000000Z
  endTime: 2024-01-01T12:00:01.000000Z
  attributes: {
    "http.method": "GET"
    "http.url": "http://localhost:8000/api/info"
    "http.status_code": 200
  }
  events: []
  links: []
  status: { code: 1 }
}
```

## 🔧 **Configuration**

### Current Configuration

The OpenTelemetry setup is configured in `OpenTelemetryServiceProvider`:

- **Exporter**: ConsoleSpanExporter (outputs to console)
- **Processor**: SimpleSpanProcessor
- **Resource**: Service name, version, and environment

### Customizing Configuration

To modify the configuration, edit `app/Providers/OpenTelemetryServiceProvider.php`:

```php
// Change exporter (e.g., to Jaeger, Zipkin, etc.)
$exporter = new JaegerExporter();

// Add batch processing
$spanProcessor = new BatchSpanProcessor($exporter);

// Add more resource attributes
$resource = ResourceInfo::create([
    ResourceAttributes::SERVICE_NAME => 'Your App Name',
    ResourceAttributes::SERVICE_VERSION => '2.0.0',
    ResourceAttributes::DEPLOYMENT_ENVIRONMENT => 'production',
    'custom.attribute' => 'value'
]);
```

## 🔌 **Integrating with External Systems**

### Jaeger Integration

To send traces to Jaeger:

```bash
composer require open-telemetry/exporter-jaeger
```

Then update the service provider:

```php
use OpenTelemetry\Contrib\Jaeger\Exporter as JaegerExporter;

$exporter = new JaegerExporter(
    'http://localhost:14268/api/traces'
);
```

### Zipkin Integration

To send traces to Zipkin:

```bash
composer require open-telemetry/exporter-zipkin
```

Then update the service provider:

```php
use OpenTelemetry\Contrib\Zipkin\Exporter as ZipkinExporter;

$exporter = new ZipkinExporter(
    'http://localhost:9411/api/v2/spans'
);
```

### OTLP Integration

To send traces via OTLP:

```bash
composer require open-telemetry/exporter-otlp
```

Then update the service provider:

```php
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;

$transport = (new OtlpHttpTransportFactory())->create(
    'http://localhost:4318/v1/traces'
);
$exporter = new SpanExporter($transport);
```

## 📊 **Monitoring and Observability**

### Key Metrics Tracked

- **Request Duration**: Time taken for each HTTP request
- **Error Rate**: Percentage of failed requests
- **Throughput**: Requests per second
- **Resource Usage**: Memory and CPU utilization
- **Custom Business Metrics**: User actions, database queries, etc.

### Trace Attributes

Each trace includes:
- HTTP method and URL
- Request headers (User-Agent, Content-Type)
- Response status code and size
- Request ID and timestamp
- Custom attributes from controllers

### Span Events

Events are added for:
- Work start/completion
- Database operations
- Cache hits/misses
- External API calls
- Error conditions

## 🛠️ **Troubleshooting**

### Common Issues

1. **No traces appearing**:
   - Check if OpenTelemetryServiceProvider is registered
   - Verify middleware is enabled
   - Check console output for errors

2. **Performance impact**:
   - Use BatchSpanProcessor for production
   - Configure sampling to reduce trace volume
   - Monitor memory usage

3. **Missing spans**:
   - Ensure controllers use OpenTelemetryTrait
   - Check for exceptions in span creation
   - Verify tracer is properly injected

### Debug Mode

Enable debug logging by adding to your controller:

```php
$this->addSpanEvent('debug.info', [
    'message' => 'Debug information',
    'data' => $someData
]);
```

## 📚 **Next Steps**

1. **Production Setup**: Configure proper exporters (Jaeger, Zipkin, etc.)
2. **Sampling**: Implement sampling strategies for high-traffic applications
3. **Custom Instrumentation**: Add tracing to database queries, cache operations
4. **Metrics**: Add OpenTelemetry metrics collection
5. **Logs**: Integrate with OpenTelemetry logging

## 🔗 **Useful Links**

- [OpenTelemetry PHP Documentation](https://opentelemetry.io/docs/instrumentation/php/)
- [Lumen Framework Documentation](https://lumen.laravel.com/docs)
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/)

---

**Note**: This integration provides a solid foundation for observability. For production use, consider implementing proper exporters and sampling strategies based on your monitoring infrastructure.

