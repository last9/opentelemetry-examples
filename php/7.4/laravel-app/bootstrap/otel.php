<?php

// Official OpenTelemetry SDK bootstrap for Laravel with optimized manual instrumentation
// This file initializes the official OpenTelemetry PHP SDK with performance-optimized batch processing

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

// Load autoloader first
require_once __DIR__ . '/../vendor/autoload.php';

// Initialize the official OpenTelemetry SDK with optimized settings
try {
    // Set up resource attributes following official SDK patterns
    $resource = \OpenTelemetry\SDK\Resource\ResourceInfoFactory::create([
        \OpenTelemetry\SemConv\ResourceAttributes::SERVICE_NAME => $_ENV['OTEL_SERVICE_NAME'] ?? 'laravel-app',
        \OpenTelemetry\SemConv\ResourceAttributes::SERVICE_VERSION => $_ENV['OTEL_SERVICE_VERSION'] ?? '1.0.0',
        \OpenTelemetry\SemConv\ResourceAttributes::DEPLOYMENT_ENVIRONMENT => $_ENV['APP_ENV'] ?? 'local',
    ]);
    
    // Create the OTLP exporter using official SDK factory with optimized settings
    $exporterFactory = new \OpenTelemetry\Contrib\Otlp\SpanExporterFactory();
    $exporter = $exporterFactory->create();
    
    // Get optimized batch processor settings from environment
    $maxQueueSize = (int)($_ENV['OTEL_BSP_MAX_QUEUE_SIZE'] ?? 2048);
    $scheduledDelayMillis = (int)($_ENV['OTEL_BSP_SCHEDULED_DELAY_MS'] ?? 5000);
    $exportTimeoutMillis = (int)($_ENV['OTEL_BSP_EXPORT_TIMEOUT_MS'] ?? 30000);
    $maxExportBatchSize = (int)($_ENV['OTEL_BSP_MAX_EXPORT_BATCH_SIZE'] ?? 512);
    
    // Create batch processor with performance-optimized official SDK settings
    $batchProcessor = new \OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor(
        $exporter,
        \OpenTelemetry\SDK\Common\Time\ClockFactory::getDefault(),
        $maxQueueSize,
        $scheduledDelayMillis,
        $exportTimeoutMillis,
        $maxExportBatchSize,
        true // autoFlush
    );
    
    // Create tracer provider with resource and batch processor
    $tracerProvider = \OpenTelemetry\SDK\Trace\TracerProviderBuilder::create()
        ->addSpanProcessor($batchProcessor)
        ->setResource($resource)
        ->build();
    
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
    
    // Register optimized shutdown function to flush remaining traces
    register_shutdown_function(function() use ($tracerProvider) {
        try {
            // Use TracerProvider shutdown which handles batch processor shutdown internally
            $tracerProvider->shutdown();
        } catch (Throwable $e) {
            // Silently handle shutdown errors to prevent application interruption
        }
    });
    
} catch (Exception $e) {
    // Log error but don't break the application - tracing should be non-intrusive
}

// Load the optimized SimpleTracer class
require_once __DIR__ . '/otel_simple.php';
    private $tracer;
    private static $instance = null;
    
    public function __construct() {
        $this->tracer = $GLOBALS['otel_tracer'] ?? null;
    }
    
    public static function getInstance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    // Optimized method for creating spans with proper lifecycle management
    public function createSpan($name, $attributes = [], $spanKind = null) {
        if (!$this->tracer) {
            return new \OpenTelemetry\API\Trace\NoopSpan(\OpenTelemetry\API\Trace\SpanContext::getInvalid());
        }
        
        $spanBuilder = $this->tracer->spanBuilder($name);
        
        // Set span kind if provided, default to INTERNAL for manual instrumentation
        if ($spanKind !== null) {
            $spanBuilder->setSpanKind($spanKind);
        } else {
            $spanBuilder->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_INTERNAL);
        }
        
        // Add attributes efficiently
        foreach ($attributes as $key => $value) {
            $spanBuilder->setAttribute($key, $value);
        }
        
        // Start span and return it for proper lifecycle management
        return $spanBuilder->startSpan();
    }
    
    // Legacy method for backward compatibility but optimized
    public function createTrace($name, $attributes = []) {
        $span = $this->createSpan($name, $attributes);
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        $span->end();
    }
    
    public function traceDatabase($query, $dbName = null, $connectionName = null, $duration = null, $rowCount = null, $error = null, $customSpanName = null) {
        if (!$this->tracer) {
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

// Initialize optimized tracer for route usage
$GLOBALS['simple_tracer'] = SimpleTracer::getInstance();

// Helper function for easy access to main tracer
if (!function_exists('otel_tracer')) {
    function otel_tracer() {
        return $GLOBALS['otel_tracer'] ?? null;
    }
}

// Backward compatibility
if (!function_exists('official_tracer')) {
    function official_tracer() {
        return $GLOBALS['otel_tracer'] ?? null;
    }
}

// Helper functions for traced operations using optimized official SDK patterns
if (!function_exists('traced_pdo_query')) {
function traced_pdo_query($pdo, $query, $params = []) {
        if (!isset($GLOBALS['otel_tracer'])) {
            $stmt = $pdo->prepare($query);
            $stmt->execute($params);
            return $stmt;
        }
        
        $operation = 'query';
        $tableName = null;
        
        // Extract operation and table name
        $queryUpper = trim(strtoupper($query));
        if (preg_match('/^(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE|REPLACE|SHOW|DESCRIBE|EXPLAIN)/', $queryUpper, $matches)) {
            $operation = strtolower($matches[1]);
        }
        
        // Extract table name based on operation
        switch ($operation) {
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
        
        $spanName = 'db.' . $operation . ($tableName ? " {$tableName}" : '');
        
        // Get current span context for parent-child relationship
        $currentSpan = \OpenTelemetry\API\Trace\Span::getCurrent();
        $spanContext = $currentSpan->getContext();
        
        $span = $GLOBALS['otel_tracer']->spanBuilder($spanName)
            ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
            ->setAttribute('db.system', 'mysql')
            ->setAttribute('db.statement', $query)
            ->setAttribute('db.operation', $operation)
            ->setAttribute('db.name', 'laravel')
            ->setAttribute('server.address', 'mysql')
            ->setAttribute('server.port', 3306)
            ->setAttribute('network.transport', 'tcp')
            ->setAttribute('network.type', 'ipv4');
        
        // Set parent context if we have a current span
        if ($spanContext->isValid()) {
            $span->setParent(\OpenTelemetry\Context\Context::getCurrent());
        }
        
        // Start the span - SDK will automatically capture start time
        $span = $span->startSpan();
        
        if ($tableName) {
            $span->setAttribute('db.sql.table', $tableName);
        }
        
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
        
        // Get current span context for parent-child relationship
        $currentSpan = \OpenTelemetry\API\Trace\Span::getCurrent();
        $spanContext = $currentSpan->getContext();
        
        $span = $GLOBALS['otel_tracer']->spanBuilder('http.client.curl')
            ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
            ->setAttribute('http.url', $url)
            ->setAttribute('http.method', 'GET');
        
        // Set parent context if we have a current span
        if ($spanContext->isValid()) {
            $span->setParent(\OpenTelemetry\Context\Context::getCurrent());
        }
        
        // Start the span - SDK will automatically capture start time
        $span = $span->startSpan();
        
        try {
            // Execute the curl request within the span timing
            $result = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            
            // Set response attributes
            $span->setAttribute('http.status_code', $httpCode);
            
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
        
        // Get current span context for parent-child relationship
        $currentSpan = \OpenTelemetry\API\Trace\Span::getCurrent();
        $spanContext = $currentSpan->getContext();
        
        $span = $GLOBALS['otel_tracer']->spanBuilder('http.client.guzzle')
            ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
            ->setAttribute('http.url', $url)
            ->setAttribute('http.method', $method);
        
        // Set parent context if we have a current span
        if ($spanContext->isValid()) {
            $span->setParent(\OpenTelemetry\Context\Context::getCurrent());
        }
        
        // Start the span - SDK will automatically capture start time
        $span = $span->startSpan();
        
        try {
            // Execute the HTTP request within the span timing
            $response = $client->request($method, $url, $options);
            
            // Set response attributes
            $span->setAttribute('http.status_code', $response->getStatusCode());
            
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

// OpenTelemetry official SDK initialized 