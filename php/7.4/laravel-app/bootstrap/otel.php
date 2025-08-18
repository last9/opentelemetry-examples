<?php

// Optimized OpenTelemetry SDK bootstrap for Laravel
// This file initializes the official OpenTelemetry PHP SDK with minimal overhead

// Load environment variables manually since Laravel hasn't loaded them yet
if (file_exists(__DIR__ . '/../.env')) {
    $lines = file(__DIR__ . '/../.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos($line, '=') !== false && strpos($line, '#') !== 0) {
            list($key, $value) = explode('=', $line, 2);
            $key = trim($key);
            $value = trim($value);
            
            // Remove quotes if present
            if (preg_match('/^"(.*)"$/', $value, $matches)) {
                $value = $matches[1];
            } elseif (preg_match("/^'(.*)'$/", $value, $matches)) {
                $value = $matches[1];
            }
            
            // Set in all environment arrays for OpenTelemetry SDK
            if (!isset($_ENV[$key])) {
                $_ENV[$key] = $value;
            }
            if (!isset($_SERVER[$key])) {
                $_SERVER[$key] = $value;
            }
            if (!getenv($key)) {
                putenv("{$key}={$value}");
            }
        }
    }
}

// Load autoloader first
require_once __DIR__ . '/../vendor/autoload.php';

// Initialize the official OpenTelemetry SDK
try {
    // Set up resource attributes following official SDK patterns
    $resourceAttributes = \OpenTelemetry\SDK\Common\Attribute\Attributes::create([
        \OpenTelemetry\SemConv\ResourceAttributes::SERVICE_NAME => $_ENV['OTEL_SERVICE_NAME'] ?? 'laravel-app',
        \OpenTelemetry\SemConv\ResourceAttributes::SERVICE_VERSION => $_ENV['OTEL_SERVICE_VERSION'] ?? '1.0.0',
        \OpenTelemetry\SemConv\ResourceAttributes::DEPLOYMENT_ENVIRONMENT => $_ENV['APP_ENV'] ?? 'local',
    ]);
    $resource = \OpenTelemetry\SDK\Resource\ResourceInfo::create($resourceAttributes);
    
    $endpoint = $_ENV['OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'] ?? 'https://otlp-aps1.last9.io:443/v1/traces';
    
    // Parse headers from environment
    $headers = [];
    $customHeaders = $_ENV['OTEL_EXPORTER_OTLP_HEADERS'] ?? '';
    if (!empty($customHeaders)) {
        $headerPairs = explode(',', $customHeaders);
        foreach ($headerPairs as $headerPair) {
            if (strpos($headerPair, '=') !== false) {
                list($key, $value) = explode('=', $headerPair, 2);
                $headers[trim($key)] = trim($value);
            }
        }
    }
    
    // Create transport and exporter using the newer, more reliable pattern
    $transport = (new \OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory())->create(
        $endpoint, 
        'application/x-protobuf',
        $headers
    );
    $exporter = new \OpenTelemetry\Contrib\Otlp\SpanExporter($transport);
    
    // Create batch processor and tracer provider using the simpler, more reliable pattern
    $batchProcessor = new \OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor(
        $exporter,
        \OpenTelemetry\SDK\Common\Time\ClockFactory::getDefault()
    );
    $tracerProvider = new \OpenTelemetry\SDK\Trace\TracerProvider($batchProcessor, null, $resource);
    
    // Get tracer instance with proper instrumentation scope
    $tracer = $tracerProvider->getTracer(
        'laravel-manual-instrumentation',
        '1.0.0',
        'https://opentelemetry.io/schemas/1.21.0'
    );
    
    // Store in globals for access throughout the application
    $GLOBALS['otel_tracer'] = $tracer;
    $GLOBALS['otel_tracer_provider'] = $tracerProvider;
    $GLOBALS['otel_batch_processor'] = $batchProcessor;
    
    // Register shutdown function to flush remaining traces
    register_shutdown_function(function() use ($tracerProvider) {
        try {
            $tracerProvider->shutdown();
        } catch (Throwable $e) {
            // Silently handle shutdown errors to prevent application interruption
        }
    });
    
} catch (Exception $e) {
    // Silently handle initialization errors - tracing should be non-intrusive
}


// Helper function for easy access to main tracer
if (!function_exists('otel_tracer')) {
    function otel_tracer() {
        return $GLOBALS['otel_tracer'] ?? null;
    }
}


// Minimal helper functions for traced operations
if (!function_exists('traced_pdo_query')) {
function traced_pdo_query($pdo, $query, $params = []) {
    if (!isset($GLOBALS['otel_tracer'])) {
        $stmt = $pdo->prepare($query);
        $stmt->execute($params);
        return $stmt;
    }
    
    // Get database configuration dynamically
    $defaultConnection = config('database.default');
    $connection = config("database.connections.{$defaultConnection}", []);
    
    // Extract table name from SQL query
    $tableName = null;
    if (preg_match('/(?:from|into|update|join)\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
        $tableName = $matches[1];
    } elseif (preg_match('/(?:table\s+)`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
        $tableName = $matches[1];
    }
    
    $spanBuilder = $GLOBALS['otel_tracer']->spanBuilder('db.query')
        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, $connection['driver'] ?? 'unknown')
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_NAME, $connection['database'] ?? $defaultConnection)
        ->setAttribute('server.address', $connection['host'] ?? 'localhost')
        ->setAttribute('server.port', $connection['port'] ?? 3306);
    
    // Add table name if extracted
    if ($tableName) {
        $spanBuilder->setAttribute('db.sql.table', $tableName);
    }
    
    $span = $spanBuilder->startSpan();
    
    try {
        // Execute the actual database operation within the span timing
        $stmt = $pdo->prepare($query);
        $stmt->execute($params);
        
        // Set row count attribute
        $span->setAttribute('db.rows_affected', $stmt->rowCount());
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        
        $span->end();
        return $stmt;
        
    } catch (Exception $e) {
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        $span->end();
        throw $e;
    }
}
}

if (!function_exists('traced_curl_exec')) {
function traced_curl_exec($ch) {
    if (!isset($GLOBALS['otel_tracer'])) {
        return curl_exec($ch);
    }
    
    $url = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
    
    $span = $GLOBALS['otel_tracer']->spanBuilder('http.client')
        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_METHOD, 'GET')
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_URL, $url)
        ->startSpan();
    
    try {
        // Execute the curl request within the span timing
        $result = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        
        // Set response attributes
        $span->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_STATUS_CODE, $httpCode);
        
        if ($httpCode >= 400) {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, 'HTTP ' . $httpCode);
        } else {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        }
        
        $span->end();
        return $result;
        
    } catch (Exception $e) {
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        $span->end();
        throw $e;
    }
}
}

if (!function_exists('traced_guzzle_request')) {
function traced_guzzle_request($client, $method, $url, $options = []) {
    if (!isset($GLOBALS['otel_tracer'])) {
        return $client->request($method, $url, $options);
    }
    
    $span = $GLOBALS['otel_tracer']->spanBuilder('http.client')
        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_METHOD, $method)
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_URL, $url)
        ->startSpan();
    
    try {
        // Execute the HTTP request within the span timing
        $response = $client->request($method, $url, $options);
        
        // Set response attributes
        $span->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_STATUS_CODE, $response->getStatusCode());
        
        if ($response->getStatusCode() >= 400) {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, 'HTTP ' . $response->getStatusCode());
        } else {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        }
        
        $span->end();
        return $response;
        
    } catch (Exception $e) {
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        $span->end();
        throw $e;
    }
}
}

if (!function_exists('fold_url')) {
function fold_url($url, $method = 'GET') {
    // Always enabled by default - no environment variable needed
    
    // Use Laravel route-based folding only
    $routeBasedFolding = fold_url_by_laravel_route($url, $method);
    if ($routeBasedFolding !== null) {
        return $routeBasedFolding;
    }
    
    // Fallback to simple method + path if no route found
    $parsedUrl = parse_url($url);
    $path = $parsedUrl['path'] ?? '/';
    return strtoupper($method) . " " . $path;
}
}

if (!function_exists('fold_url_by_laravel_route')) {
function fold_url_by_laravel_route($url, $method = 'GET') {
    // Only work if Laravel is available and routes are loaded
    if (!function_exists('app') || !app()->bound('router')) {
        return null;
    }
    
    try {
        $router = app('router');
        $parsedUrl = parse_url($url);
        $path = $parsedUrl['path'] ?? '/';
        
        // Remove leading slash to match Laravel route patterns
        $path = ltrim($path, '/');
        
        // Get all registered routes
        $routes = $router->getRoutes();
        if (empty($routes)) {
            return null;
        }
        
        // Find matching route by path and method
        foreach ($routes as $route) {
            $routePath = $route->uri();
            $routeMethods = $route->methods();
            
            // Check if method matches
            if (!in_array(strtoupper($method), $routeMethods)) {
                continue;
            }
            
            // Try to match the path to the route pattern
            $pattern = $routePath;
            
            // Convert Laravel route parameters to regex pattern
            $pattern = preg_replace('/\{([^}]+)\}/', '([^/]+)', $pattern);
            $pattern = '#^' . $pattern . '$#';
            
            if (preg_match($pattern, $path)) {
                // Found matching route, always use the route pattern with parameter placeholders
                $foldedPath = "/" . $route->uri();
                return strtoupper($method) . " " . $foldedPath;
            }
        }
        
        return null;
        
    } catch (Exception $e) {
        // Silently fall back to pattern-based folding
        return null;
    }
}
}

if (!function_exists('traced_http_request')) {
function traced_http_request($method, $url, $options = [], $context = []) {
    if (!isset($GLOBALS['otel_tracer'])) {
        // Fallback to basic HTTP request if no tracer
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_HTTPHEADER => $options['headers'] ?? [],
            CURLOPT_POSTFIELDS => $options['data'] ?? null,
            CURLOPT_TIMEOUT => $options['timeout'] ?? 30,
        ]);
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return ['body' => $response, 'status' => $httpCode];
    }
    
    // Fold URL for better trace grouping
    $foldedUrl = fold_url($url, $method);
    
    $span = $GLOBALS['otel_tracer']->spanBuilder('http.client')
        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_METHOD, $method)
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_URL, $url)
        ->setAttribute('http.folded_url', $foldedUrl)
        ->setAttribute('http.route_pattern', $foldedUrl)
        ->startSpan();
    
    // Add context attributes if provided
    if (!empty($context['service'])) {
        $span->setAttribute('http.service', $context['service']);
    }
    if (!empty($context['operation'])) {
        $span->setAttribute('http.operation', $context['operation']);
    }
    
    try {
        // Execute the HTTP request
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_HTTPHEADER => $options['headers'] ?? [],
            CURLOPT_POSTFIELDS => $options['data'] ?? null,
            CURLOPT_TIMEOUT => $options['timeout'] ?? 30,
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);
        
        if ($error) {
            throw new Exception("cURL error: {$error}");
        }
        
        // Set response attributes
        $span->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::HTTP_STATUS_CODE, $httpCode);
        
        if ($httpCode >= 400) {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, 'HTTP ' . $httpCode);
        } else {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        }
        
        $span->end();
        return ['body' => $response, 'status' => $httpCode];
        
    } catch (Exception $e) {
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        $span->end();
        throw $e;
    }
}
}

if (!function_exists('traced_laravel_route')) {
function traced_laravel_route($routeName, $parameters = [], $absolute = true) {
    if (!isset($GLOBALS['otel_tracer'])) {
        // Fallback to basic route generation if no tracer
        return route($routeName, $parameters, $absolute);
    }
    
    $span = $GLOBALS['otel_tracer']->spanBuilder('route.generation')
        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_INTERNAL)
        ->setAttribute('route.name', $routeName)
        ->setAttribute('route.parameters', json_encode($parameters))
        ->setAttribute('route.absolute', $absolute)
        ->startSpan();
    
    try {
        $url = route($routeName, $parameters, $absolute);
        
        // Fold the generated URL
        $foldedUrl = fold_url($url);
        
        $span->setAttribute('route.generated_url', $url);
        $span->setAttribute('route.folded_url', $foldedUrl);
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        $span->end();
        
        return $url;
        
    } catch (Exception $e) {
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        $span->end();
        throw $e;
    }
}
}

if (!function_exists('traced_redis_command')) {
function traced_redis_command($redis, $command, $args = []) {
    if (!isset($GLOBALS['otel_tracer'])) {
        return call_user_func_array([$redis, $command], $args);
    }
    
    $span = $GLOBALS['otel_tracer']->spanBuilder('redis.' . strtolower($command))
        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
        ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, 'redis')
        ->setAttribute('db.operation', strtoupper($command))
        ->setAttribute('redis.command', strtoupper($command))
        ->startSpan();
    
    // Add key information for better observability
    if (!empty($args) && is_string($args[0])) {
        $span->setAttribute('redis.key', $args[0]);
    }
    
    try {
        $result = call_user_func_array([$redis, $command], $args);
        
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        $span->end();
        
        return $result;
        
    } catch (Exception $e) {
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        $span->end();
        throw $e;
    }
}
}

if (!function_exists('traced_redis_get')) {
function traced_redis_get($key) {
    if (!extension_loaded('redis')) {
        throw new Exception('Please make sure the PHP Redis extension is installed and enabled.');
    }
    $redis = app('redis')->connection();
    return traced_redis_command($redis, 'get', [$key]);
}
}

if (!function_exists('traced_redis_set')) {
function traced_redis_set($key, $value, $expiry = null) {
    if (!extension_loaded('redis')) {
        throw new Exception('Please make sure the PHP Redis extension is installed and enabled.');
    }
    $redis = app('redis')->connection();
    if ($expiry !== null) {
        return traced_redis_command($redis, 'setex', [$key, $expiry, $value]);
    } else {
        return traced_redis_command($redis, 'set', [$key, $value]);
    }
}
}

if (!function_exists('traced_redis_del')) {
function traced_redis_del($key) {
    if (!extension_loaded('redis')) {
        throw new Exception('Please make sure the PHP Redis extension is installed and enabled.');
    }
    $redis = app('redis')->connection();
    return traced_redis_command($redis, 'del', [$key]);
}
}

if (!function_exists('traced_queue_push')) {
function traced_queue_push($job, $data = [], $queue = null) {
    if (!isset($GLOBALS['otel_tracer'])) {
        return app('queue')->push($job, $data, $queue);
    }
    
    $queueDriver = config('queue.default', 'sync');
    $messagingSystem = $queueDriver === 'redis' ? 'redis' : $queueDriver;
    
    $span = $GLOBALS['otel_tracer']->spanBuilder('queue.push')
        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_PRODUCER)
        ->setAttribute('messaging.system', $messagingSystem)
        ->setAttribute('messaging.destination.name', $queue ?? 'default')
        ->setAttribute('messaging.operation', 'publish')
        ->setAttribute('queue.job.class', is_string($job) ? $job : get_class($job))
        ->setAttribute('queue.driver', $queueDriver)
        ->startSpan();
    
    try {
        // Inject trace context into job payload for propagation
        $traceContext = [];
        \OpenTelemetry\API\Trace\Propagation\TraceContextPropagator::getInstance()->inject($traceContext);
        
        // Add trace context to job data
        if (is_object($job) && method_exists($job, 'setTraceContext')) {
            $job->setTraceContext($traceContext);
        }
        
        $result = app('queue')->push($job, $data, $queue);
        
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        $span->end();
        
        return $result;
        
    } catch (Exception $e) {
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        $span->end();
        throw $e;
    }
}
}
