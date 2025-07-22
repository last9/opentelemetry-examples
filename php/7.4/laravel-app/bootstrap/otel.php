<?php

// Manual OpenTelemetry instrumentation bootstrap for Laravel
// This file initializes basic OpenTelemetry configuration and utilities

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

class Last9Tracer
{
    private static $instance = null;
    private $collectorUrl;
    private $headers;
    
    private function __construct()
    {
        // Use $_ENV directly since Laravel functions are not available during bootstrap
        $this->collectorUrl = $_ENV['OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'] ?? 'http://localhost:4318/v1/traces';
        $this->headers = ['Content-Type' => 'application/json'];
        // Parse OTEL_EXPORTER_OTLP_HEADERS if set
        $headers = $_ENV['OTEL_EXPORTER_OTLP_HEADERS'] ?? '';
        if (!empty($headers)) {
            $headerPairs = explode(',', $headers);
            foreach ($headerPairs as $pair) {
                $kv = explode('=', $pair, 2);
                if (count($kv) === 2) {
                    $key = urldecode(trim($kv[0]));
                    $value = urldecode(trim($kv[1]));
                    $this->headers[$key] = $value;
                }
            }
        }
        

    }
    
    public static function getInstance()
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    public function createSpan($name, $kind = 1, $attributes = [])
    {
        return [
            'traceId' => bin2hex(random_bytes(16)),
            'spanId' => bin2hex(random_bytes(8)),
            'name' => $name,
            'kind' => $kind, // 1=INTERNAL, 2=SERVER, 3=CLIENT, 4=PRODUCER, 5=CONSUMER
            'startTime' => microtime(true),
            'attributes' => $attributes
        ];
    }
    
    public function finishSpan($span, $status = 1, $statusMessage = null)
    {
        $span['endTime'] = microtime(true);
        $span['status'] = ['code' => $status];
        if ($statusMessage) {
            $span['status']['message'] = $statusMessage;
        }
        // Synchronous export: send this span immediately
        $spanArr = [
            'traceId' => $span['traceId'],
            'spanId' => $span['spanId'],
            'name' => $span['name'],
            'kind' => $span['kind'],
            'startTimeUnixNano' => (int)($span['startTime'] * 1000000000),
            'endTimeUnixNano' => (int)($span['endTime'] * 1000000000),
            'attributes' => $span['attributes'],
            'status' => $span['status']
        ];
        if (isset($span['parentSpanId'])) {
            $spanArr['parentSpanId'] = $span['parentSpanId'];
        }
        $traceData = [
            'resourceSpans' => [
                [
                    'resource' => [
                        'attributes' => [
                            ['key' => 'service.name', 'value' => ['stringValue' => $_ENV['OTEL_SERVICE_NAME'] ?? 'laravel-app']],
                            ['key' => 'service.version', 'value' => ['stringValue' => $_ENV['OTEL_SERVICE_VERSION'] ?? '1.0.0']],
                            ['key' => 'service.instance.id', 'value' => ['stringValue' => gethostname() . '-' . getmypid()]],
                            ['key' => 'deployment.environment', 'value' => ['stringValue' => $_ENV['APP_ENV'] ?? 'production']],
                            ['key' => 'process.runtime.name', 'value' => ['stringValue' => 'php']],
                            ['key' => 'process.runtime.version', 'value' => ['stringValue' => PHP_VERSION]],
                            ['key' => 'process.pid', 'value' => ['intValue' => getmypid()]],
                            ['key' => 'telemetry.sdk.name', 'value' => ['stringValue' => 'opentelemetry-php-manual']],
                            ['key' => 'telemetry.sdk.version', 'value' => ['stringValue' => '1.0.0']],
                            ['key' => 'telemetry.sdk.language', 'value' => ['stringValue' => 'php']],
                        ]
                    ],
                    'scopeSpans' => [
                        [
                            'scope' => ['name' => 'laravel-manual-tracer', 'version' => '1.0.0'],
                            'spans' => [ $spanArr ]
                        ]
                    ]
                ]
            ]
        ];
        try {
            $client = new \GuzzleHttp\Client([
                'timeout' => 2.0,
                'verify' => false
            ]);
            $client->post($this->collectorUrl, [
                'json' => $traceData,
                'headers' => $this->headers
            ]);
        } catch (Exception $e) {
            // Silently fail - tracing should not break the application
        }
        return $span;
    }
}

// Initialize global tracer
$GLOBALS['manual_tracer'] = Last9Tracer::getInstance();

// Simple tracer class for easy usage
class SimpleTracer {
    private $tracer;
    
    public function __construct() {
        $this->tracer = Last9Tracer::getInstance();
    }
    
    public function createTrace($name, $attributes = []) {
        $span = $this->tracer->createSpan($name, 1, $this->formatAttributes($attributes));
        $this->tracer->finishSpan($span);
    }
    
    public function traceDatabase($query, $dbName = null, $connectionName = null, $duration = null, $rowCount = null, $error = null, $customSpanName = null) {
        $operation = $this->extractDbOperation($query);
        $tableName = $this->extractTableName($query, $operation);
        
        // Use custom span name if provided (for Eloquent events), otherwise use default
        if ($customSpanName) {
            $spanName = $customSpanName;
        } else {
            $spanName = 'db.' . $operation . ($tableName ? " {$tableName}" : '');
        }
        
        $traceId = isset($GLOBALS['otel_trace_id']) ? $GLOBALS['otel_trace_id'] : bin2hex(random_bytes(16));
        $parentSpanId = isset($GLOBALS['otel_span_id']) ? $GLOBALS['otel_span_id'] : null;
        $spanId = bin2hex(random_bytes(8));
        $startTime = microtime(true);
        $endTime = $startTime + ($duration ? $duration / 1000 : 0.001);
        $attributes = [
            ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
            ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
            ['key' => 'db.operation', 'value' => ['stringValue' => $operation]],
            ['key' => 'db.name', 'value' => ['stringValue' => $dbName ?? $_ENV['DB_DATABASE'] ?? 'laravel']],
            ['key' => 'server.address', 'value' => ['stringValue' => $_ENV['DB_HOST'] ?? 'mysql']],
            ['key' => 'server.port', 'value' => ['intValue' => (int)($_ENV['DB_PORT'] ?? 3306)]],
            ['key' => 'network.transport', 'value' => ['stringValue' => 'tcp']],
            ['key' => 'network.type', 'value' => ['stringValue' => 'ipv4']],
            ['key' => 'db.user', 'value' => ['stringValue' => $_ENV['DB_USERNAME'] ?? 'root']],
        ];
        if ($tableName) {
            $attributes[] = ['key' => 'db.sql.table', 'value' => ['stringValue' => $tableName]];
        }
        if ($duration !== null) {
            $attributes[] = ['key' => 'db.duration', 'value' => ['stringValue' => (string)$duration]];
        }
        if ($rowCount !== null) {
            $attributes[] = ['key' => 'db.rows_affected', 'value' => ['intValue' => (int)$rowCount]];
        }
        // OpenTelemetry error semantic conventions
        if ($error) {
            $attributes[] = ['key' => 'exception.type', 'value' => ['stringValue' => is_object($error) ? get_class($error) : 'database_error']];
            $attributes[] = ['key' => 'exception.message', 'value' => ['stringValue' => is_object($error) ? $error->getMessage() : (string)$error]];
            if (is_object($error) && method_exists($error, 'getTraceAsString')) {
                $attributes[] = ['key' => 'exception.stacktrace', 'value' => ['stringValue' => $error->getTraceAsString()]];
            }
        }
        $span = [
            'traceId' => $traceId,
            'spanId' => $spanId,
            'name' => $spanName,
            'kind' => 3, // CLIENT
            'startTime' => $startTime,
            'endTime' => $endTime,
            'attributes' => $attributes,
            'status' => [
                'code' => $error ? 2 : 1,
                'message' => $error ? (is_object($error) ? $error->getMessage() : (string)$error) : null
            ]
        ];
        if ($parentSpanId) {
            $span['parentSpanId'] = $parentSpanId;
        }
        $this->tracer->finishSpan($span, $span['status']['code'], $span['status']['message']);
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
                if (preg_match('/\bFROM\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'create':
                if (preg_match('/\bTABLE\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'drop':
                if (preg_match('/\bTABLE\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'alter':
                if (preg_match('/\bTABLE\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'truncate':
                if (preg_match('/\bTRUNCATE\s+(?:TABLE\s+)?`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
        }
        
        return $tableName;
    }
    
    private function formatAttributes($attributes) {
        $formatted = [];
        foreach ($attributes as $key => $value) {
            $formatted[] = ['key' => $key, 'value' => ['stringValue' => (string)$value]];
        }
        return $formatted;
    }
}

// Initialize simple tracer for route usage
$GLOBALS['simple_tracer'] = new SimpleTracer();

// Helper function for easy access
if (!function_exists('tracer')) {
    function tracer() {
        return $GLOBALS['manual_tracer'];
    }
}

// OpenTelemetry manual instrumentation initialized