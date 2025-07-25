# Complete OpenTelemetry Setup Guide for Your Laravel App

## 📁 Files to Copy

Copy these 3 essential files from this project to your Laravel app:

```
bootstrap/otel.php                           # Core OpenTelemetry SDK setup
app/Http/Middleware/OpenTelemetryMiddleware.php  # HTTP request/response tracing  
app/Providers/AppServiceProvider.php            # Database tracing (copy the boot() method)
```

## 🔧 Integration Steps

### 1. **Update `public/index.php`**
Add this line after the autoloader, before Laravel bootstrap:

```php
// Initialize OpenTelemetry SDK
require_once __DIR__.'/../bootstrap/otel.php';
```

### 2. **Register HTTP Middleware**
In `app/Http/Kernel.php`, add to the `$middleware` array:

```php
protected $middleware = [
    // ... existing middleware
    \App\Http\Middleware\OpenTelemetryMiddleware::class,
];
```

### 3. **Add Database Tracing**
In your existing `AppServiceProvider.php` `boot()` method, add this code:

```php
public function boot()
{
    $tracer = $GLOBALS['otel_tracer'] ?? null;
    
    \Illuminate\Support\Facades\DB::listen(function ($query) use ($tracer) {
        if (!$tracer) {
            return;
        }
        
        try {
            $span = $tracer->spanBuilder('db.query')
                ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, 'mysql')
                ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_NAME, $query->connectionName ?? 'laravel')
                ->setAttribute('server.address', 'localhost')
                ->setAttribute('server.port', 3306)
                ->setAttribute('db.statement', $query->sql)
                ->setAttribute('db.query.duration_ms', $query->time)
                ->startSpan();
            
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
            $span->end();
            
        } catch (\Throwable $e) {
            // Silently fail
        }
    });
}
```

### 4. **Environment Variables**
Add to your `.env` file:

```env
OTEL_SERVICE_NAME=your-app-name
OTEL_SERVICE_VERSION=1.0.0
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://your-collector-endpoint/v1/traces
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic your-auth-token"
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

### 5. **Composer Dependencies**
Add to your `composer.json` and run `composer install`:

```json
{
    "require": {
        "open-telemetry/sdk": "^1.0",
        "open-telemetry/contrib-otlp": "^1.0",
        "open-telemetry/sem-conv": "^1.0"
    }
}
```

## 🎯 What You'll Get

- ✅ **HTTP Request Spans** - All incoming requests traced automatically
- ✅ **Database Spans** - All Eloquent ORM and raw DB queries traced  
- ✅ **External HTTP Call Tracing** - Use helper functions `traced_curl_exec()` and `traced_guzzle_request()`
- ✅ **Proper Span Relationships** - Database spans are children of HTTP request spans
- ✅ **Performance Optimized** - Zero regex parsing, minimal overhead

## 🚀 Optional: External HTTP Calls

For tracing external HTTP calls, use these helper functions (included in `bootstrap/otel.php`):

```php
// Instead of curl_exec($ch)
$result = traced_curl_exec($ch);

// Instead of $client->request($method, $url, $options)  
$response = traced_guzzle_request($client, $method, $url, $options);
```

## 🔍 Testing Your Setup

After integration, test that tracing is working:

### Quick Test Endpoints
You can add these test routes to verify everything is working:

```php
// Test basic functionality
Route::get('/test-otel', function () {
    // This will create HTTP span automatically via middleware
    
    // Test database span
    $users = \Illuminate\Support\Facades\DB::select('SELECT COUNT(*) as count FROM users');
    
    // Test external HTTP call (if needed)
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://httpbin.org/get');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $result = traced_curl_exec($ch);
    curl_close($ch);
    
    return response()->json([
        'message' => 'OpenTelemetry test completed',
        'user_count' => $users[0]->count ?? 0,
        'external_call' => 'success'
    ]);
});
```

### Verification Checklist
- [ ] HTTP request span appears in your tracing backend
- [ ] Database query spans appear as children of HTTP span
- [ ] External HTTP call spans appear (if using helper functions)
- [ ] All spans contain proper semantic attributes
- [ ] No application errors or performance degradation

## 🐛 Troubleshooting

### Common Issues

1. **No spans appearing**
   - Check environment variables are set correctly
   - Verify collector endpoint is reachable
   - Check Laravel logs for any errors

2. **Database spans missing**
   - Ensure `AppServiceProvider.php` boot method includes the DB::listen code
   - Verify database queries are actually executing

3. **HTTP spans missing**
   - Confirm middleware is registered in `Kernel.php`
   - Check middleware order (should be early in the stack)

4. **Performance issues**
   - This implementation is optimized for minimal overhead
   - Monitor your application performance before/after
   - Adjust batch processor settings in `bootstrap/otel.php` if needed

## 📚 Additional Resources

- [OpenTelemetry PHP Documentation](https://opentelemetry.io/docs/php/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Laravel Service Providers](https://laravel.com/docs/providers)
- [Laravel Middleware](https://laravel.com/docs/middleware)

---

That's it! Your Laravel app will now have comprehensive OpenTelemetry tracing with HTTP, database, and external call monitoring.