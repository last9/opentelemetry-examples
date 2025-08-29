# Simple OpenTelemetry Error Tracing - Copy & Paste Guide

## Quick Start - Just Copy & Paste These Code Blocks

### 1. Add to Your Controller (Copy this exactly)

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use App\Traits\OpenTelemetryTrait;

class YourController extends Controller
{
    use OpenTelemetryTrait;

    // ✅ COPY THIS METHOD - Basic error tracing
    public function yourMethod(Request $request): JsonResponse
    {
        return $this->traceOperation('your.operation.name', function () use ($request) {
            // Your existing code goes here
            try {
                // Example: Database operation
                $user = User::find($request->id);
                if (!$user) {
                    return response()->json(['error' => 'User not found'], 404);
                }
                
                return response()->json(['user' => $user]);
            } catch (\Exception $e) {
                // This will automatically be traced as an error
                throw $e;
            }
        }, [
            'controller' => 'YourController',
            'method' => 'yourMethod'
        ]);
    }

    // ✅ COPY THIS METHOD - Database error tracing
    public function getUser($id): JsonResponse
    {
        return $this->traceDatabaseQuery(
            'SELECT * FROM users WHERE id = ?',
            [$id],
            function () use ($id) {
                $user = User::find($id);
                if (!$user) {
                    throw new \Exception('User not found');
                }
                return response()->json(['user' => $user]);
            }
        );
    }

    // ✅ COPY THIS METHOD - API call error tracing
    public function callExternalApi(): JsonResponse
    {
        return $this->traceExternalApiCall(
            'https://api.example.com/data',
            'GET',
            function () {
                $client = new \GuzzleHttp\Client();
                $response = $client->get('https://api.example.com/data');
                return response()->json(['data' => $response->getBody()]);
            }
        );
    }

    // ✅ COPY THIS METHOD - Cache operation error tracing
    public function getCachedData($key): JsonResponse
    {
        return $this->traceCacheOperation(
            'get',
            $key,
            function () use ($key) {
                $data = Cache::get($key);
                if (!$data) {
                    throw new \Exception('Cache miss');
                }
                return response()->json(['data' => $data]);
            }
        );
    }
}
```

### 2. Test Your Error Tracing (Copy these curl commands)

```bash
# Test basic error
curl -X GET "http://localhost:8000/api/error?type=exception"

# Test 404 error
curl -X GET "http://localhost:8000/api/error?type=not_found"

# Test 500 error
curl -X GET "http://localhost:8000/api/error?type=server_error"

# Test division by zero
curl -X GET "http://localhost:8000/api/division-by-zero"

# Test undefined variable
curl -X GET "http://localhost:8000/api/undefined-variable"
```

### 3. What Gets Traced Automatically

When you use the code above, these errors are automatically captured:

- ✅ **HTTP Status Codes** (404, 500, etc.)
- ✅ **Exception Messages** 
- ✅ **Stack Traces**
- ✅ **File and Line Numbers**
- ✅ **Request/Response Details**
- ✅ **Database Query Errors**
- ✅ **API Call Failures**
- ✅ **Cache Operation Errors**

### 4. Add Custom Error Attributes (Optional)

```php
// Add this inside your traceOperation callback
public function yourMethod(Request $request): JsonResponse
{
    return $this->traceOperation('your.operation.name', function () use ($request) {
        // Add custom error context
        $this->setSpanAttribute('user.id', $request->user()->id);
        $this->setSpanAttribute('operation.type', 'user_lookup');
        
        // Your code here...
        
    }, [
        'controller' => 'YourController'
    ]);
}
```

### 5. Record Custom Error Events (Optional)

```php
// Add this inside your traceOperation callback
public function yourMethod(Request $request): JsonResponse
{
    return $this->traceOperation('your.operation.name', function () use ($request) {
        // Record custom events
        $this->addSpanEvent('user.authenticated', [
            'user_id' => $request->user()->id,
            'timestamp' => now()->toISOString()
        ]);
        
        // Your code here...
        
    }, [
        'controller' => 'YourController'
    ]);
}
```

## That's It! 🎉

Just copy the code blocks above into your controller and your errors will be automatically traced. No complex setup needed!

## What You'll See in Your Observability Platform

- **Error Rate**: How many errors occur
- **Error Types**: What kinds of errors happen
- **Stack Traces**: Full error details for debugging
- **Request Context**: Which endpoints are failing
- **Performance Impact**: How errors affect response times

## Need Help?

If you see errors in your traces, check:
1. ✅ You added `use OpenTelemetryTrait;` to your controller
2. ✅ You wrapped your code in `$this->traceOperation()`
3. ✅ Your OpenTelemetry endpoint is configured correctly

## Advanced Usage (Optional)

### Using the Error Service Directly

```php
use App\Services\OpenTelemetryErrorService;

class YourService
{
    protected OpenTelemetryErrorService $errorService;

    public function __construct(OpenTelemetryErrorService $errorService)
    {
        $this->errorService = $errorService;
    }

    public function doSomething()
    {
        return $this->errorService->traceOperation('service.operation', function () {
            // Your service code here
        });
    }
}
```

### Environment Configuration

Make sure these are set in your `.env` file:

```env
OTEL_SERVICE_NAME=your-app-name
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

That's it! Your errors are now being traced automatically. 🚀
