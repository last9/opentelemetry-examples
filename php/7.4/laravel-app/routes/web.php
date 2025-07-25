<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\DB;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
|
| Here is where you can register web routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| contains the "web" middleware group. Now create something great!
|
*/

Route::get('/', function () {
    return response()->json([
        'message' => 'Laravel PHP 7.4 with OpenTelemetry',
        'timestamp' => date('Y-m-d H:i:s'),
        'php_version' => PHP_VERSION,
        'laravel_version' => app()->version()
    ]);
});

// Example routes showing OpenTelemetry tracing capabilities
Route::get('/api/health', function () {
    return response()->json([
        'status' => 'healthy',
        'timestamp' => date('Y-m-d H:i:s')
    ]);
});


Route::get('/api/example', function () {
    // Example of custom tracing in your application using official SDK
            if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->createTrace('business.logic', [
            'operation' => 'example_processing',
            'user_id' => 'anonymous'
        ]);
    }
    
    return response()->json([
        'message' => 'Example endpoint with official SDK tracing',
        'traced' => true
    ]);
});

// Test routes for official SDK export functionality
Route::get('/api/test-batch', function () {
    $startTime = microtime(true);
    
    // Generate multiple traces to test batching
    for ($i = 1; $i <= 25; $i++) {
        if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->createTrace("batch.test.{$i}", [
                'iteration' => $i,
                'test_type' => 'batch_processing',
                'timestamp' => microtime(true)
            ]);
        }
    }
    
    $duration = (microtime(true) - $startTime) * 1000;
    
    return response()->json([
        'message' => 'Official SDK batch test completed',
        'traces_generated' => 25,
        'duration_ms' => round($duration, 2),
        'timestamp' => date('Y-m-d H:i:s')
    ]);
});

Route::get('/api/test-async', function () {
    $startTime = microtime(true);
    
    // Generate traces asynchronously
    for ($i = 1; $i <= 25; $i++) {
        if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->createTrace("async.test.{$i}", [
                'iteration' => $i,
                'test_type' => 'async_processing',
                'timestamp' => microtime(true)
            ]);
        }
    }
    
    $duration = (microtime(true) - $startTime) * 1000;
    
    return response()->json([
        'message' => 'Official SDK async test completed',
        'traces_generated' => 25,
        'duration_ms' => round($duration, 2),
        'timestamp' => date('Y-m-d H:i:s')
    ]);
});

// Test official SDK batch processor status
Route::get('/api/test-batch-status', function () {
    try {
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
            
            return response()->json([
                'message' => 'Official SDK batch processor status',
                'flush_result' => $flushResult,
                'processor_type' => 'BatchSpanProcessor',
                'timestamp' => date('Y-m-d H:i:s')
            ]);
        } else {
            return response()->json([
                'error' => 'OpenTelemetry batch processor not available',
                'timestamp' => date('Y-m-d H:i:s')
            ], 500);
        }
    } catch (Exception $e) {
        return response()->json([
            'error' => 'Failed to get batch processor status',
            'message' => $e->getMessage()
        ], 500);
    }
});

// Test official SDK force flush
Route::get('/api/test-force-flush', function () {
    try {
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
            
            return response()->json([
                'message' => 'Official SDK force flush completed',
                'flush_result' => $flushResult,
                'timestamp' => date('Y-m-d H:i:s')
            ]);
        } else {
            return response()->json([
                'error' => 'OpenTelemetry batch processor not available',
                'timestamp' => date('Y-m-d H:i:s')
            ], 500);
        }
    } catch (Exception $e) {
        return response()->json([
            'error' => 'Failed to force flush',
            'message' => $e->getMessage()
        ], 500);
    }
});

// Test performance with official SDK
Route::get('/api/test-performance', function () {
    $results = [];
    
    // Test 1: Single trace
    $startTime = microtime(true);
            if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->createTrace('performance.single', ['test' => 'single']);
        }
    $singleDuration = (microtime(true) - $startTime) * 1000;
    $results['single_trace_ms'] = round($singleDuration, 3);
    
    // Test 2: Multiple traces (should be batched)
    $startTime = microtime(true);
    for ($i = 1; $i <= 20; $i++) {
        if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->createTrace("performance.batch.{$i}", ['test' => 'batch']);
        }
    }
    $batchDuration = (microtime(true) - $startTime) * 1000;
    $results['batch_20_traces_ms'] = round($batchDuration, 3);
    $results['avg_per_trace_ms'] = round($batchDuration / 20, 3);
    
    // Test 3: Database tracing
    $startTime = microtime(true);
    try {
        DB::select('SELECT 1 as test');
        $dbDuration = (microtime(true) - $startTime) * 1000;
        $results['db_trace_ms'] = round($dbDuration, 3);
    } catch (Exception $e) {
        $results['db_trace_error'] = $e->getMessage();
    }
    
    return response()->json([
        'message' => 'Performance test completed',
        'results' => $results,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
});

// Test configuration
Route::get('/api/test-config', function () {
    return response()->json([
        'message' => 'Configuration retrieved',
        'config' => [
            'service_name' => env('OTEL_SERVICE_NAME', 'laravel-app'),
            'service_version' => env('OTEL_SERVICE_VERSION', '1.0.0'),
            'endpoint' => env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'http://localhost:4318/v1/traces'),
            'headers' => env('OTEL_EXPORTER_OTLP_HEADERS', ''),
            'protocol' => env('OTEL_EXPORTER_OTLP_PROTOCOL', 'http/protobuf'),
            // OpenTelemetry SDK Standard Batch Span Processor settings
            'max_export_batch_size' => env('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', 2048),
            'max_queue_size' => env('OTEL_BSP_MAX_QUEUE_SIZE', 2048),
            'scheduled_delay_ms' => env('OTEL_BSP_SCHEDULED_DELAY_MS', 5000),
            'export_timeout_ms' => env('OTEL_BSP_EXPORT_TIMEOUT_MS', 30000),
            'max_concurrent_exports' => env('OTEL_BSP_MAX_CONCURRENT_EXPORTS', 1),
        ],
        'timestamp' => date('Y-m-d H:i:s')
    ]);
});

// Test database operations with tracing
Route::get('/api/test-db', function () {
    try {
        // Test database operations with tracing
        $users = DB::select('SELECT COUNT(*) as count FROM users');
        $userCount = $users[0]->count ?? 0;
        
        // Create a test user if table is empty
        if ($userCount == 0) {
            DB::insert('INSERT INTO users (name, email, password, created_at, updated_at) VALUES (?, ?, ?, ?, ?)', [
                'Test User',
                'test@example.com',
                bcrypt('password'),
                now(),
                now()
            ]);
            $userCount = 1;
        }
        
        return response()->json([
            'message' => 'Database test completed',
            'user_count' => $userCount,
            'traced' => true,
            'timestamp' => date('Y-m-d H:i:s')
        ]);
    } catch (Exception $e) {
        return response()->json([
            'error' => 'Database test failed',
            'message' => $e->getMessage()
        ], 500);
    }
});

// Test custom spans
Route::get('/api/test-custom-spans', function () {
    try {
        if (isset($GLOBALS['otel_tracer'])) {
            // Create a custom span
            $span = $GLOBALS['otel_tracer']->spanBuilder('custom.operation')
                ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_INTERNAL)
                ->setAttribute('custom.attribute', 'test_value')
                ->setAttribute('operation.type', 'test_operation')
                ->startSpan();
            
            // Simulate some work
            usleep(100000); // 100ms
            
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
            $span->end();
            
            return response()->json([
                'message' => 'Custom span created successfully',
                'span_name' => 'custom.operation',
                'duration_ms' => 100,
                'timestamp' => date('Y-m-d H:i:s')
            ]);
        } else {
            return response()->json([
                'error' => 'OpenTelemetry tracer not available',
                'timestamp' => date('Y-m-d H:i:s')
            ], 500);
        }
    } catch (Exception $e) {
        return response()->json([
            'error' => 'Failed to create custom span',
            'message' => $e->getMessage()
        ], 500);
    }
});

// Test slow operations
Route::get('/api/test-slow', function () {
    try {
        if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->createTrace('slow.operation', [
                'operation_type' => 'simulated_work',
                'duration_ms' => 500,
                'complexity' => 'high'
            ]);
        }
        
        // Simulate slow operation
        usleep(500000); // 500ms
        
        return response()->json([
            'message' => 'Slow operation completed',
            'duration_ms' => 500,
            'traced' => true,
            'timestamp' => date('Y-m-d H:i:s')
        ]);
    } catch (Exception $e) {
        return response()->json([
            'error' => 'Slow operation failed',
            'message' => $e->getMessage()
        ], 500);
    }
});

// Test cURL operations with tracing
Route::get('/api/joke-curl', function () {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://official-joke-api.appspot.com/random_joke');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    $result = traced_curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    $data = json_decode($result, true);
    return response()->json([
        'message' => 'Joke fetched with curl',
        'http_code' => $httpCode,
        'joke' => $data
    ]);
});

// Test Guzzle operations with tracing
Route::get('/api/joke-guzzle', function () {
    $client = new \GuzzleHttp\Client();
    try {
        $response = traced_guzzle_request($client, 'GET', 'https://official-joke-api.appspot.com/random_joke');
        $data = json_decode($response->getBody()->getContents(), true);
        return response()->json([
            'message' => 'Joke fetched with Guzzle',
            'http_code' => $response->getStatusCode(),
            'joke' => $data
        ]);
    } catch (Exception $e) {
        return response()->json([
            'message' => 'Failed to fetch joke with Guzzle',
            'error' => $e->getMessage()
        ], 500);
    }
});

// Eloquent ORM example for OpenTelemetry DB tracing
date_default_timezone_set('UTC');
use App\User;

Route::get('/api/eloquent-example', function () {
    // Fetch paginated users using Eloquent ORM
    $users = User::where('email', 'like', '%@%')->paginate(5);
    
    // Return paginated users as JSON
    return response()->json([
        'message' => 'Eloquent ORM paginated users',
        'users' => $users->items(),
        'pagination' => [
            'current_page' => $users->currentPage(),
            'last_page' => $users->lastPage(),
            'total' => $users->total(),
        ]
    ]);
});

// Test official OpenTelemetry SDK batch exporter (using global tracer)
Route::get('/test-official-otel', function () {
    try {
        if (!isset($GLOBALS['simple_tracer'])) {
            throw new Exception('OpenTelemetry tracer not initialized');
        }
        
        // Create some test traces
        $GLOBALS['simple_tracer']->createTrace('test.otel.simple', [
            'test.type' => 'sdk',
            'test.message' => 'Using official OpenTelemetry SDK batch exporter'
        ]);
        
        // Test database tracing
        $GLOBALS['simple_tracer']->traceDatabase(
            'SELECT * FROM users WHERE id = 1',
            'laravel',
            'mysql',
            15.5,
            1
        );
        
        // Force flush to see immediate results
        $flushResult = false;
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
        }
        
        return response()->json([
            'status' => 'success',
            'message' => 'Official OpenTelemetry SDK traces created and flushed',
            'flush_result' => $flushResult,
            'timestamp' => now()->toISOString()
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => 'Failed to create traces with official SDK',
            'error' => $e->getMessage(),
            'trace' => $e->getTraceAsString()
        ], 500);
    }
});

// Test database spans with official SDK
Route::get('/test-db-spans', function () {
    try {
        if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->traceDatabase('SELECT * FROM users WHERE id = 1', 'laravel', 'mysql', 25.5, 1);
            $GLOBALS['simple_tracer']->traceDatabase('INSERT INTO logs (message, created_at) VALUES (?, ?)', 'laravel', 'mysql', 18.2, 1);
            $GLOBALS['simple_tracer']->traceDatabase('UPDATE users SET last_login = ? WHERE id = ?', 'laravel', 'mysql', 12.8, 1);
        }
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
        } else {
            $flushResult = false;
        }
        return response()->json([
            'status' => 'success',
            'message' => 'Database spans test completed',
            'spans_created' => 3,
            'flush_result' => $flushResult,
            'timestamp' => now()->toISOString()
        ]);
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => 'Database spans test failed',
            'error' => $e->getMessage()
        ], 500);
    }
});

// Test all trace types with official SDK
Route::get('/test-all-traces', function () {
    try {
        $results = [];
        $results['http_server_span'] = 'Generated by middleware for this request';
        
        if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->createTrace('business.logic.user_processing', [
                'operation' => 'user_processing',
                'user_id' => 'test_user_123',
                'priority' => 'high'
            ]);
            $GLOBALS['simple_tracer']->createTrace('business.logic.notification', [
                'operation' => 'notification_send',
                'type' => 'email',
                'recipient' => 'user@example.com'
            ]);
            $results['custom_spans'] = 'Created 2 business logic spans';
        }
        
        if (isset($GLOBALS['simple_tracer'])) {
            $GLOBALS['simple_tracer']->traceDatabase(
                'SELECT * FROM users WHERE email = ?',
                'laravel',
                'mysql',
                15.2,
                1
            );
            $GLOBALS['simple_tracer']->traceDatabase(
                'UPDATE users SET last_activity = ? WHERE id = ?',
                'laravel',
                'mysql',
                8.7,
                1
            );
            $GLOBALS['simple_tracer']->traceDatabase(
                'INSERT INTO audit_logs (action, user_id, timestamp) VALUES (?, ?, ?)',
                'laravel',
                'mysql',
                12.3,
                1
            );
            $results['database_spans'] = 'Created 3 database spans (SELECT, UPDATE, INSERT)';
        }
        
        if (isset($GLOBALS['otel_tracer'])) {
            $span = $GLOBALS['otel_tracer']->spanBuilder('http.client.external_api')
                ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                ->startSpan();
            usleep(50000); // 50ms
            $span->setAttribute('http.status_code', 200)
                ->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK)
                ->end();
            $results['http_client_spans'] = 'Created 1 HTTP client span';
        }
        
        if (isset($GLOBALS['otel_tracer'])) {
            $span = $GLOBALS['otel_tracer']->spanBuilder('cache.operation')
                ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_INTERNAL)
                ->startSpan();
            $span->setAttribute('cache.hit', false)
                ->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK)
                ->end();
            $results['cache_spans'] = 'Created 1 cache operation span';
        }
        
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
            $results['flush_result'] = $flushResult;
        } else {
            $results['flush_result'] = false;
        }
        
        $results['total_spans_created'] = '8 spans (1 HTTP server + 2 business logic + 3 database + 1 HTTP client + 1 cache)';
        $results['timestamp'] = now()->toISOString();
        $results['message'] = 'All trace types tested successfully';
        
        return response()->json($results);
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => 'Comprehensive trace test failed',
            'error' => $e->getMessage()
        ], 500);
    }
});

// Test traced PDO query
Route::get('/test-traced-pdo', function () {
    try {
        // Create a PDO connection
        $pdo = new PDO('mysql:host=localhost;dbname=laravel', 'root', '');
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        // Test traced PDO query
        $result = traced_pdo_query($pdo, 'SELECT * FROM users LIMIT 1');
        $row = $result->fetch(PDO::FETCH_ASSOC);
        
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
        } else {
            $flushResult = false;
        }
        
        return response()->json([
            'status' => 'success',
            'message' => 'PDO query test completed',
            'data_found' => !empty($row),
            'flush_result' => $flushResult,
            'timestamp' => now()->toISOString()
        ]);
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => 'PDO query test failed',
            'error' => $e->getMessage()
        ], 500);
    }
});

// Test traced curl
Route::get('/test-traced-curl', function () {
    try {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'https://httpbin.org/get');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        
        $result = traced_curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
        } else {
            $flushResult = false;
        }
        
        return response()->json([
            'status' => 'success',
            'message' => 'Curl test completed',
            'http_code' => $httpCode,
            'response_size' => strlen($result),
            'flush_result' => $flushResult,
            'timestamp' => now()->toISOString()
        ]);
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => 'Curl test failed',
            'error' => $e->getMessage()
        ], 500);
    }
});

// Test traced Guzzle
Route::get('/test-traced-guzzle', function () {
    try {
        $client = new \GuzzleHttp\Client();
        $response = traced_guzzle_request($client, 'GET', 'https://httpbin.org/get');
        
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
        } else {
            $flushResult = false;
        }
        
        return response()->json([
            'status' => 'success',
            'message' => 'Guzzle test completed',
            'http_code' => $response->getStatusCode(),
            'response_size' => strlen($response->getBody()->getContents()),
            'flush_result' => $flushResult,
            'timestamp' => now()->toISOString()
        ]);
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => 'Guzzle test failed',
            'error' => $e->getMessage()
        ], 500);
    }
});

// Test database timing verification
Route::get('/test-db-timing-detailed', function () {
    $results = [];
    
    // Test 1: Simple SELECT with timing measurement
    $start = microtime(true);
    try {
        $users = DB::select('SELECT 1 as test');
        $actualDuration = (microtime(true) - $start) * 1000; // Convert to ms
        $results['simple_select'] = [
            'query' => 'SELECT 1 as test',
            'actual_duration_ms' => round($actualDuration, 3),
            'result_count' => count($users),
            'success' => true
        ];
    } catch (Exception $e) {
        $results['simple_select'] = [
            'query' => 'SELECT 1 as test',
            'error' => $e->getMessage(),
            'success' => false
        ];
    }
    
    // Test 2: COUNT query with timing
    $start = microtime(true);
    try {
        $count = DB::select('SELECT COUNT(*) as count FROM users');
        $actualDuration = (microtime(true) - $start) * 1000;
        $results['count_query'] = [
            'query' => 'SELECT COUNT(*) as count FROM users',
            'actual_duration_ms' => round($actualDuration, 3),
            'count' => $count[0]->count ?? 0,
            'success' => true
        ];
    } catch (Exception $e) {
        $results['count_query'] = [
            'query' => 'SELECT COUNT(*) as count FROM users',
            'error' => $e->getMessage(),
            'success' => false
        ];
    }
    
    // Test 3: Multiple queries to check consistency
    $timings = [];
    for ($i = 0; $i < 5; $i++) {
        $start = microtime(true);
        try {
            DB::select('SELECT ? as iteration', [$i]);
            $timings[] = round((microtime(true) - $start) * 1000, 3);
        } catch (Exception $e) {
            $timings[] = 'ERROR: ' . $e->getMessage();
        }
    }
    
    $results['multiple_queries'] = [
        'query' => 'SELECT ? as iteration (5 times)',
        'individual_timings_ms' => $timings,
        'avg_timing_ms' => is_numeric($timings[0]) ? round(array_sum($timings) / count($timings), 3) : 'N/A',
        'min_timing_ms' => is_numeric($timings[0]) ? min($timings) : 'N/A',
        'max_timing_ms' => is_numeric($timings[0]) ? max($timings) : 'N/A'
    ];
    
    // Force flush spans
    $flushResult = false;
    if (isset($GLOBALS['otel_batch_processor'])) {
        $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
    }
    
    return response()->json([
        'message' => 'Database timing verification completed',
        'timing_tests' => $results,
        'flush_result' => $flushResult,
        'note' => 'Compare actual_duration_ms with span attributes in your telemetry backend',
        'timestamp' => now()->toISOString()
    ]);
});

// Test database span timing verification with logging
Route::get('/test-db-span-timing-verification', function () {
    $results = [];
    $spanTimings = [];
    
    // Capture DB query events with detailed timing
    DB::listen(function ($query) use (&$spanTimings) {
        $spanTimings[] = [
            'sql' => $query->sql,
            'laravel_reported_time_ms' => $query->time,
            'connection' => $query->connectionName
        ];
    });
    
    // Test 1: Simple query
    $start = microtime(true);
    DB::select('SELECT 1 as test');
    $actualTime1 = round((microtime(true) - $start) * 1000, 3);
    
    // Test 2: COUNT query  
    $start = microtime(true);
    DB::select('SELECT COUNT(*) as count FROM users');
    $actualTime2 = round((microtime(true) - $start) * 1000, 3);
    
    // Test 3: More complex query
    $start = microtime(true);
    DB::select('SELECT * FROM users LIMIT 5');
    $actualTime3 = round((microtime(true) - $start) * 1000, 3);
    
    $results = [
        'query_timing_comparison' => [
            [
                'query' => 'SELECT 1 as test',
                'measured_duration_ms' => $actualTime1,
                'laravel_reported_ms' => $spanTimings[0]['laravel_reported_time_ms'] ?? 'N/A',
                'difference_ms' => $actualTime1 - ($spanTimings[0]['laravel_reported_time_ms'] ?? 0)
            ],
            [
                'query' => 'SELECT COUNT(*) as count FROM users', 
                'measured_duration_ms' => $actualTime2,
                'laravel_reported_ms' => $spanTimings[1]['laravel_reported_time_ms'] ?? 'N/A',
                'difference_ms' => $actualTime2 - ($spanTimings[1]['laravel_reported_time_ms'] ?? 0)
            ],
            [
                'query' => 'SELECT * FROM users LIMIT 5',
                'measured_duration_ms' => $actualTime3, 
                'laravel_reported_ms' => $spanTimings[2]['laravel_reported_time_ms'] ?? 'N/A',
                'difference_ms' => $actualTime3 - ($spanTimings[2]['laravel_reported_time_ms'] ?? 0)
            ]
        ]
    ];
    
    // Force flush spans
    $flushResult = false;
    if (isset($GLOBALS['otel_batch_processor'])) {
        $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
    }
    
    return response()->json([
        'message' => 'Database span timing verification completed',
        'results' => $results,
        'explanation' => [
            'measured_duration_ms' => 'Time measured by microtime() in application code',
            'laravel_reported_ms' => 'Time reported by Laravel\'s DB::listen() (used in span attributes)',
            'difference_ms' => 'Difference between measured and reported (should be small)',
            'span_attributes' => 'The span will have db.query.duration_ms attribute with Laravel reported time'
        ],
        'flush_result' => $flushResult,
        'timestamp' => now()->toISOString()
    ]);
});

// Diagnostic endpoint to check DB span generation
Route::get('/diagnostic-db-spans', function () {
    $diagnostics = [];
    
    // Check if OpenTelemetry tracer is available
    $diagnostics['otel_tracer_available'] = isset($GLOBALS['otel_tracer']);
    $diagnostics['otel_batch_processor_available'] = isset($GLOBALS['otel_batch_processor']);
    
    // Test simple database query
    $diagnostics['db_query_test'] = 'starting';
    try {
        $result = DB::select('SELECT 1 as diagnostic_test');
        $diagnostics['db_query_test'] = 'success';
        $diagnostics['db_result'] = $result[0]->diagnostic_test ?? 'no_result';
    } catch (Exception $e) {
        $diagnostics['db_query_test'] = 'failed: ' . $e->getMessage();
    }
    
    // Force flush spans
    $flushResult = false;
    if (isset($GLOBALS['otel_batch_processor'])) {
        try {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
            $diagnostics['flush_result'] = $flushResult;
        } catch (Exception $e) {
            $diagnostics['flush_error'] = $e->getMessage();
        }
    }
    
    return response()->json([
        'message' => 'Database span diagnostics',
        'diagnostics' => $diagnostics,
        'timestamp' => now()->toISOString()
    ]);
});

// Test span export configuration and status
Route::get('/test-span-export-status', function () {
    $status = [];
    
    // Check OpenTelemetry configuration
    $status['otel_config'] = [
        'service_name' => env('OTEL_SERVICE_NAME', 'laravel-app'),
        'endpoint' => env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'http://localhost:4318/v1/traces'),
        'protocol' => env('OTEL_EXPORTER_OTLP_PROTOCOL', 'http/protobuf'),
        'headers' => env('OTEL_EXPORTER_OTLP_HEADERS', ''),
    ];
    
    // Test database query
    $queryStart = microtime(true);
    try {
        DB::select('SELECT 1 as export_test');
        $status['db_query'] = 'success';
        $status['db_query_time_ms'] = round((microtime(true) - $queryStart) * 1000, 3);
    } catch (Exception $e) {
        $status['db_query'] = 'failed: ' . $e->getMessage();
    }
    
    // Check batch processor status
    if (isset($GLOBALS['otel_batch_processor'])) {
        $status['batch_processor'] = 'available';
        try {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
            $status['flush_result'] = $flushResult ? 'success' : 'failed';
        } catch (Exception $e) {
            $status['flush_error'] = $e->getMessage();
        }
    } else {
        $status['batch_processor'] = 'not_available';
    }
    
    // Test basic span creation
    if (isset($GLOBALS['otel_tracer'])) {
        try {
            $testSpan = $GLOBALS['otel_tracer']->spanBuilder('test.export.verification')
                ->setAttribute('test.type', 'export_status_check')
                ->setAttribute('test.timestamp', microtime(true))
                ->startSpan();
            $testSpan->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
            $testSpan->end();
            $status['test_span'] = 'created';
        } catch (Exception $e) {
            $status['test_span'] = 'failed: ' . $e->getMessage();
        }
    } else {
        $status['test_span'] = 'tracer_not_available';
    }
    
    return response()->json([
        'message' => 'Span export status check',
        'status' => $status,
        'note' => 'Check your OpenTelemetry collector logs to see if spans are being received',
        'timestamp' => now()->toISOString()
    ]);
});

// Test all traced functions together
Route::get('/test-all-traced-functions', function () {
    try {
        $results = [];
        
        // Test PDO
        try {
            $pdo = new PDO('mysql:host=localhost;dbname=laravel', 'root', '');
            $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $result = traced_pdo_query($pdo, 'SELECT * FROM users LIMIT 1');
            $results['pdo_test'] = 'SUCCESS';
        } catch (Exception $e) {
            $results['pdo_test'] = 'FAILED: ' . $e->getMessage();
        }
        
        // Test cURL
        try {
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, 'https://httpbin.org/get');
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            $result = traced_curl_exec($ch);
            curl_close($ch);
            $results['curl_test'] = 'SUCCESS';
        } catch (Exception $e) {
            $results['curl_test'] = 'FAILED: ' . $e->getMessage();
        }
        
        // Test Guzzle
        try {
            $client = new \GuzzleHttp\Client();
            $response = traced_guzzle_request($client, 'GET', 'https://httpbin.org/get');
            $results['guzzle_test'] = 'SUCCESS';
        } catch (Exception $e) {
            $results['guzzle_test'] = 'FAILED: ' . $e->getMessage();
        }
        
        // Force flush
        if (isset($GLOBALS['otel_batch_processor'])) {
            $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
            $results['flush_result'] = $flushResult;
        } else {
            $results['flush_result'] = false;
        }
        
        $results['message'] = 'All traced functions test completed';
        $results['timestamp'] = now()->toISOString();
        
        return response()->json($results);
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => 'All traced functions test failed',
            'error' => $e->getMessage()
        ], 500);
    }
});
