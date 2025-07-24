<?php

// Official OpenTelemetry SDK bootstrap for Laravel
// This file initializes the official OpenTelemetry PHP SDK with batch processing

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
            
            // Only set if not already set in environment
            if (!isset($_ENV[$key])) {
                $_ENV[$key] = $value;
            }
        }
    }
}

// Set up environment variables for the official SDK



// Load autoloader first
require_once __DIR__ . '/../vendor/autoload.php';

// Initialize the official OpenTelemetry SDK
try {
    // Create the OTLP exporter using the official factory
    $exporterFactory = new \OpenTelemetry\Contrib\Otlp\SpanExporterFactory();
    $exporter = $exporterFactory->create();
    
    // Create clock for batch processor
    $clock = \OpenTelemetry\SDK\Common\Time\ClockFactory::getDefault();
    
    // Create batch processor with official SDK defaults
    $batchProcessor = new \OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor(
        $exporter,
        $clock,
        2048,    // maxQueueSize
        5000,    // scheduledDelayMillis
        30000,   // exportTimeoutMillis
        512,     // maxExportBatchSize
        true     // autoFlush
    );
    
    // Create tracer provider with batch processor
    $tracerProvider = (new \OpenTelemetry\SDK\Trace\TracerProviderBuilder())
        ->addSpanProcessor($batchProcessor)
        ->build();
    
    // Get tracer instance
    $tracer = $tracerProvider->getTracer(
        'laravel-app',
        '1.0.0'
    );
    
    // Store in globals for access throughout the application
    $GLOBALS['official_tracer'] = $tracer;
    $GLOBALS['official_tracer_provider'] = $tracerProvider;
    $GLOBALS['official_batch_processor'] = $batchProcessor;
    
    // Log successful initialization
    error_log('OpenTelemetry SDK initialized successfully');
    error_log('Endpoint: ' . getenv('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'));
    error_log('Service: laravel-app');
    
    // Register shutdown function to flush remaining traces
    register_shutdown_function(function() use ($batchProcessor, $tracerProvider) {
        error_log('Shutdown function called - flushing traces');
        $batchProcessor->shutdown();
        $tracerProvider->shutdown();
        error_log('Shutdown function completed');
    });
    
} catch (Exception $e) {
    // Log error but don't break the application
    error_log('Failed to initialize OpenTelemetry SDK: ' . $e->getMessage());
    error_log('Stack trace: ' . $e->getTraceAsString());
}

// Simple tracer class for easy usage with official SDK
class SimpleTracer {
    private $tracer;
    
    public function __construct() {
        $this->tracer = $GLOBALS['official_tracer'] ?? null;
    }
    
    public function createTrace($name, $attributes = []) {
        if (!$this->tracer) {
            error_log('No tracer available for createTrace: ' . $name);
            return;
        }
        
        // Get current span context for parent-child relationship
        $currentSpan = \OpenTelemetry\API\Trace\Span::getCurrent();
        $spanContext = $currentSpan->getContext();
        
        $span = $this->tracer->spanBuilder($name)
            ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_INTERNAL);
        
        // Add attributes
        foreach ($attributes as $key => $value) {
            $span->setAttribute($key, $value);
        }
        
        // Set parent context if we have a current span
        if ($spanContext->isValid()) {
            $span->setParent(\OpenTelemetry\Context\Context::getCurrent());
        }
        
        $span = $span->startSpan();
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        $span->end();
        
        error_log('Created trace: ' . $name . ' with parent: ' . ($spanContext->isValid() ? 'yes' : 'no'));
    }
    
    public function traceDatabase($query, $dbName = null, $connectionName = null, $duration = null, $rowCount = null, $error = null, $customSpanName = null) {
        if (!$this->tracer) {
            error_log('No tracer available for traceDatabase: ' . $query);
            return;
        }
        
        $operation = $this->extractDbOperation($query);
        $tableName = $this->extractTableName($query, $operation);
        
        $spanName = $customSpanName ?: 'db.' . $operation . ($tableName ? " {$tableName}" : '');
        
        // Get current span context for parent-child relationship
        $currentSpan = \OpenTelemetry\API\Trace\Span::getCurrent();
        $spanContext = $currentSpan->getContext();
        
        $span = $this->tracer->spanBuilder($spanName)
            ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
            ->setAttribute('db.system', 'mysql')
            ->setAttribute('db.statement', $query)
            ->setAttribute('db.operation', $operation)
            ->setAttribute('db.name', $dbName ?? 'laravel')
            ->setAttribute('server.address', 'mysql')
            ->setAttribute('server.port', 3306)
            ->setAttribute('network.transport', 'tcp')
            ->setAttribute('network.type', 'ipv4');
        
        // Set parent context if we have a current span
        if ($spanContext->isValid()) {
            $span->setParent(\OpenTelemetry\Context\Context::getCurrent());
        }
        
        $span = $span->startSpan();
        
        if ($tableName) {
            $span->setAttribute('db.sql.table', $tableName);
        }
        
        if ($duration !== null) {
            $span->setAttribute('db.duration', (string)$duration);
        }
        
        if ($rowCount !== null) {
            $span->setAttribute('db.rows_affected', $rowCount);
        }
        
        if ($error) {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $error->getMessage());
            $span->recordException($error);
        } else {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        }
        
        $span->end();
        
        error_log('Created database trace: ' . $spanName . ' with parent: ' . ($spanContext->isValid() ? 'yes' : 'no'));
    }
    
    private function extractDbOperation($query) {
        $query = trim(strtoupper($query));
        if (preg_match('/^(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE|REPLACE|SHOW|DESCRIBE|EXPLAIN)/', $query, $matches)) {
            return strtolower($matches[1]);
        }
        return 'query';
    }
    
    private function extractTableName($query, $operation) {
        $query = trim($query);
        $tableName = null;
        
        switch (strtolower($operation)) {
            case 'select':
                if (preg_match('/\bFROM\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'insert':
                if (preg_match('/\bINTO\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'update':
                if (preg_match('/\bUPDATE\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'delete':
                if (preg_match('/\bFROM\s+`?([a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
        }
        
        return $tableName;
    }
}

// Initialize simple tracer for route usage
$GLOBALS['official_simple_tracer'] = new SimpleTracer();

// Helper function for easy access
if (!function_exists('official_tracer')) {
    function official_tracer() {
        return $GLOBALS['official_tracer'] ?? null;
    }
}

// Helper functions for traced operations using official SDK
if (!function_exists('traced_pdo_query')) {
function traced_pdo_query($pdo, $query, $params = []) {
        $startTime = microtime(true);
        try {
            $stmt = $pdo->prepare($query);
            $stmt->execute($params);
            $duration = (microtime(true) - $startTime) * 1000;
            
            if (isset($GLOBALS['official_simple_tracer'])) {
                $GLOBALS['official_simple_tracer']->traceDatabase($query, null, null, $duration, $stmt->rowCount());
            }
            
            return $stmt;
        } catch (Exception $e) {
            $duration = (microtime(true) - $startTime) * 1000;
            if (isset($GLOBALS['official_simple_tracer'])) {
                $GLOBALS['official_simple_tracer']->traceDatabase($query, null, null, $duration, null, $e);
            }
            throw $e;
        }
    }
}

if (!function_exists('traced_curl_exec')) {
function traced_curl_exec($ch) {
        if (!isset($GLOBALS['official_tracer'])) {
            return curl_exec($ch);
        }
        
        $startTime = microtime(true);
        $result = curl_exec($ch);
        $duration = (microtime(true) - $startTime) * 1000;
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $url = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
        
        $span = $GLOBALS['official_tracer']->spanBuilder('http.client.curl')
            ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
            ->setAttribute('http.url', $url)
            ->setAttribute('http.status_code', $httpCode)
            ->setAttribute('http.duration_ms', $duration)
            ->setAttribute('http.method', 'GET')
            ->startSpan();
        
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        $span->end();
        
        return $result;
    }
}

if (!function_exists('traced_guzzle_request')) {
function traced_guzzle_request($client, $method, $url, $options = []) {
        if (!isset($GLOBALS['official_tracer'])) {
            return $client->request($method, $url, $options);
        }
        
        $startTime = microtime(true);
        try {
            $response = $client->request($method, $url, $options);
            $duration = (microtime(true) - $startTime) * 1000;
            
            $span = $GLOBALS['official_tracer']->spanBuilder('http.client.guzzle')
                ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                ->setAttribute('http.url', $url)
                ->setAttribute('http.method', $method)
                ->setAttribute('http.status_code', $response->getStatusCode())
                ->setAttribute('http.duration_ms', $duration)
                ->startSpan();
            
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
            $span->end();
            
            return $response;
        } catch (Exception $e) {
            $duration = (microtime(true) - $startTime) * 1000;
            
            $span = $GLOBALS['official_tracer']->spanBuilder('http.client.guzzle.error')
                ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                ->setAttribute('http.url', $url)
                ->setAttribute('http.method', $method)
                ->setAttribute('http.duration_ms', $duration)
                ->setAttribute('error.message', $e->getMessage())
                ->startSpan();
            
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            $span->end();
            
            throw $e;
        }
    }
}

// OpenTelemetry official SDK initialized 