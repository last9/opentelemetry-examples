<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Validation\ValidationException;
use App\Traits\OpenTelemetryTrait;
use Carbon\Carbon;

class TestController extends Controller
{
    use OpenTelemetryTrait;
    /**
     * Get application information
     */
    public function info(): JsonResponse
    {
        return $this->traceOperation('app.info', function () {
            $this->setSpanAttribute('app.name', config('app.name', 'Lumen Test App'));
            $this->setSpanAttribute('app.environment', config('app.env', 'local'));
            $this->setSpanAttribute('php.version', PHP_VERSION);
            
            $this->addSpanEvent('info.retrieved', [
                'memory_usage' => memory_get_usage(true),
                'peak_memory' => memory_get_peak_usage(true)
            ]);

            return response()->json([
                'app_name' => config('app.name', 'Lumen Test App'),
                'environment' => config('app.env', 'local'),
                'debug' => config('app.debug', false),
                'php_version' => PHP_VERSION,
                'lumen_version' => app()->version(),
                'server_time' => Carbon::now()->toISOString(),
                'memory_usage' => memory_get_usage(true),
                'peak_memory' => memory_get_peak_usage(true)
            ]);
        }, [
            'operation' => 'get_app_info',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Test validation
     */
    public function validateRequest(Request $request): JsonResponse
    {
        try {
            $validated = $this->validate($request, [
                'name' => 'required|string|max:255',
                'email' => 'required|email',
                'age' => 'integer|min:18|max:120',
                'interests' => 'array',
                'interests.*' => 'string'
            ]);

            return response()->json([
                'status' => 'success',
                'message' => 'Validation passed',
                'data' => $validated
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors()
            ], 422);
        }
    }

    /**
     * Test error handling
     */
    public function error(Request $request): JsonResponse
    {
        $type = $request->get('type', 'general');
        
        switch ($type) {
            case 'not_found':
                return response()->json(['error' => 'Resource not found'], 404);
            case 'unauthorized':
                return response()->json(['error' => 'Unauthorized access'], 401);
            case 'forbidden':
                return response()->json(['error' => 'Access forbidden'], 403);
            case 'server_error':
                return response()->json(['error' => 'Internal server error'], 500);
            case 'exception':
                throw new \Exception('This is a test exception');
            default:
                return response()->json(['error' => 'General error'], 400);
        }
    }

    /**
     * Test file upload simulation
     */
    public function upload(Request $request): JsonResponse
    {
        $file = $request->file('file');
        
        if (!$file) {
            return response()->json([
                'status' => 'error',
                'message' => 'No file uploaded'
            ], 400);
        }

        // Simulate file processing
        $fileInfo = [
            'original_name' => $file->getClientOriginalName(),
            'mime_type' => $file->getMimeType(),
            'size' => $file->getSize(),
            'extension' => $file->getClientOriginalExtension(),
            'uploaded_at' => Carbon::now()->toISOString()
        ];

        return response()->json([
            'status' => 'success',
            'message' => 'File uploaded successfully',
            'file_info' => $fileInfo
        ]);
    }

    /**
     * Test pagination simulation
     */
    public function paginated(Request $request): JsonResponse
    {
        $page = (int) $request->get('page', 1);
        $perPage = (int) $request->get('per_page', 10);
        $total = 100; // Simulate total records
        
        // Generate fake data
        $data = [];
        $start = ($page - 1) * $perPage;
        
        for ($i = 0; $i < min($perPage, $total - $start); $i++) {
            $data[] = [
                'id' => $start + $i + 1,
                'title' => 'Item ' . ($start + $i + 1),
                'description' => 'Description for item ' . ($start + $i + 1),
                'created_at' => Carbon::now()->subDays(rand(1, 30))->toISOString()
            ];
        }

        return response()->json([
            'data' => $data,
            'pagination' => [
                'current_page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'last_page' => ceil($total / $perPage),
                'from' => $start + 1,
                'to' => min($start + $perPage, $total)
            ]
        ]);
    }

    /**
     * Test caching simulation
     */
    public function cache(Request $request): JsonResponse
    {
        $key = $request->get('key', 'test_key');
        $action = $request->get('action', 'get');
        
        switch ($action) {
            case 'set':
                $value = $request->get('value', 'cached_value');
                // In a real app, you'd use: Cache::put($key, $value, 3600);
                return response()->json([
                    'status' => 'success',
                    'message' => "Value cached with key: {$key}",
                    'key' => $key,
                    'value' => $value
                ]);
            
            case 'get':
                // In a real app, you'd use: $value = Cache::get($key);
                $value = "cached_value_for_{$key}";
                return response()->json([
                    'status' => 'success',
                    'key' => $key,
                    'value' => $value,
                    'cached_at' => Carbon::now()->toISOString()
                ]);
            
            case 'delete':
                // In a real app, you'd use: Cache::forget($key);
                return response()->json([
                    'status' => 'success',
                    'message' => "Cache key deleted: {$key}"
                ]);
            
            default:
                return response()->json([
                    'status' => 'error',
                    'message' => 'Invalid action. Use: set, get, or delete'
                ], 400);
        }
    }

    /**
     * Test OpenTelemetry tracing functionality
     */
    public function traceTest(Request $request): JsonResponse
    {
        return $this->traceOperation('trace.test', function () use ($request) {
            $this->setSpanAttribute('test.type', 'opentelemetry_demo');
            $this->setSpanAttribute('test.timestamp', Carbon::now()->toISOString());
            
            // Simulate some work
            $this->addSpanEvent('work.started', ['step' => 'initialization']);
            
            usleep(100000); // 100ms delay
            
            $this->addSpanEvent('work.processing', ['step' => 'data_processing']);
            
            usleep(50000); // 50ms delay
            
            $this->addSpanEvent('work.completed', ['step' => 'finalization']);
            
            return response()->json([
                'status' => 'success',
                'message' => 'OpenTelemetry tracing test completed',
                'trace_id' => $this->getCurrentTraceId(),
                'span_id' => $this->getCurrentSpanId(),
                'timestamp' => Carbon::now()->toISOString(),
                'test_data' => [
                    'random_number' => rand(1, 1000),
                    'memory_usage' => memory_get_usage(true),
                    'request_id' => uniqid()
                ]
            ]);
        }, [
            'operation' => 'trace_test',
            'controller' => 'TestController',
            'request_method' => $request->method()
        ]);
    }

    /**
     * Test external API call tracing
     */
    public function externalApiTest(Request $request): JsonResponse
    {
        return $this->traceExternalApiCall(
            'https://httpbin.org/json',
            'GET',
            function () {
                $this->addSpanEvent('api.call.started', ['endpoint' => 'httpbin']);
                
                // Simulate external API call
                usleep(200000); // 200ms delay
                
                $this->addSpanEvent('api.call.completed', ['status' => 'success']);
                
                return new JsonResponse([
                    'status' => 'success',
                    'message' => 'External API call traced',
                    'trace_id' => $this->getCurrentTraceId(),
                    'data' => [
                        'external_api_response' => 'simulated_response',
                        'response_time' => '200ms'
                    ]
                ]);
            }
        );
    }

    /**
     * Test database query tracing
     */
    public function databaseTest(Request $request): JsonResponse
    {
        return $this->traceDatabaseQuery(
            'SELECT * FROM users WHERE id = ?',
            [1],
            function () {
                $this->addSpanEvent('db.query.started', ['table' => 'users']);
                
                // Simulate database query
                usleep(50000); // 50ms delay
                
                $this->addSpanEvent('db.query.completed', ['rows_returned' => 1]);
                
                return new JsonResponse([
                    'status' => 'success',
                    'message' => 'Database query traced',
                    'trace_id' => $this->getCurrentTraceId(),
                    'data' => [
                        'query_executed' => 'SELECT * FROM users WHERE id = 1',
                        'execution_time' => '50ms',
                        'result' => 'simulated_user_data'
                    ]
                ]);
            }
        );
    }

    /**
     * Test cache operation tracing
     */
    public function cacheTest(Request $request): JsonResponse
    {
        $key = $request->get('key', 'test_key');
        
        return $this->traceCacheOperation(
            'get',
            $key,
            function () use ($key) {
                $this->addSpanEvent('cache.operation.started', ['key' => $key]);
                
                // Simulate cache operation
                usleep(10000); // 10ms delay
                
                $this->addSpanEvent('cache.operation.completed', ['hit' => true]);
                
                return new JsonResponse([
                    'status' => 'success',
                    'message' => 'Cache operation traced',
                    'trace_id' => $this->getCurrentTraceId(),
                    'data' => [
                        'cache_key' => $key,
                        'operation' => 'get',
                        'cache_hit' => true,
                        'execution_time' => '10ms'
                    ]
                ]);
            }
        );
    }

    /**
     * Get current trace ID
     */
    private function getCurrentTraceId(): string
    {
        try {
            $tracer = app(\OpenTelemetry\API\Trace\TracerInterface::class);
            // For now, return a placeholder since we need proper span context management
            return 'trace-id-not-available';
        } catch (\Exception $e) {
            return 'trace-id-not-available';
        }
    }

    /**
     * Get current span ID
     */
    private function getCurrentSpanId(): string
    {
        try {
            $tracer = app(\OpenTelemetry\API\Trace\TracerInterface::class);
            // For now, return a placeholder since we need proper span context management
            return 'span-id-not-available';
        } catch (\Exception $e) {
            return 'span-id-not-available';
        }
    }

    /**
     * Trigger division by zero error
     */
    public function divisionByZero(): JsonResponse
    {
        return $this->traceOperation('error.division_by_zero', function () {
            $result = 10 / 0;
            return response()->json(['result' => $result]);
        }, [
            'error_type' => 'division_by_zero',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger undefined variable error
     */
    public function undefinedVariable(): JsonResponse
    {
        return $this->traceOperation('error.undefined_variable', function () {
            return response()->json(['undefined_var' => $undefinedVariable]);
        }, [
            'error_type' => 'undefined_variable',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger array access error
     */
    public function arrayAccessError(): JsonResponse
    {
        return $this->traceOperation('error.array_access', function () {
            $array = [1, 2, 3];
            return response()->json(['value' => $array[10]]);
        }, [
            'error_type' => 'array_access',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger file not found error
     */
    public function fileNotFound(): JsonResponse
    {
        return $this->traceOperation('error.file_not_found', function () {
            $content = file_get_contents('/non/existent/file.txt');
            return response()->json(['content' => $content]);
        }, [
            'error_type' => 'file_not_found',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger database connection error
     */
    public function databaseConnectionError(): JsonResponse
    {
        return $this->traceOperation('error.database_connection', function () {
            throw new \Exception('Database connection failed: Connection refused');
        }, [
            'error_type' => 'database_connection',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger custom exception
     */
    public function customException(): JsonResponse
    {
        return $this->traceOperation('error.custom_exception', function () {
            throw new \InvalidArgumentException('This is a custom invalid argument exception');
        }, [
            'error_type' => 'custom_exception',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger JSON decode error
     */
    public function jsonDecodeError(): JsonResponse
    {
        return $this->traceOperation('error.json_decode', function () {
            $invalidJson = '{"invalid": json}';
            $data = json_decode($invalidJson, true);
            return response()->json(['data' => $data]);
        }, [
            'error_type' => 'json_decode',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger HTTP client error
     */
    public function httpClientError(): JsonResponse
    {
        return $this->traceOperation('error.http_client', function () {
            $client = new \GuzzleHttp\Client();
            $response = $client->get('http://invalid-domain-that-does-not-exist-12345.com');
            return response()->json(['response' => $response->getBody()]);
        }, [
            'error_type' => 'http_client',
            'controller' => 'TestController'
        ]);
    }

    /**
     * Trigger multiple errors in sequence
     */
    public function multipleErrors(): JsonResponse
    {
        return $this->traceOperation('error.multiple_errors', function () {
            $errors = [];
            
            try {
                $result = 10 / 0;
            } catch (\Exception $e) {
                $errors[] = 'Division by zero: ' . $e->getMessage();
            }
            
            try {
                $undefinedVar;
            } catch (\Exception $e) {
                $errors[] = 'Undefined variable: ' . $e->getMessage();
            }
            
            try {
                $array = [1, 2, 3];
                $array[10];
            } catch (\Exception $e) {
                $errors[] = 'Array access: ' . $e->getMessage();
            }
            
            return response()->json(['errors' => $errors]);
        }, [
            'error_type' => 'multiple_errors',
            'controller' => 'TestController'
        ]);
    }
}
