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