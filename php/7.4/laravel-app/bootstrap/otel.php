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
                // Removed db.user to prevent credential leakage
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

// Helper function to sanitize URLs and remove sensitive data
if (!function_exists('sanitize_url_for_tracing')) {
    function sanitize_url_for_tracing($url) {
        $parsedUrl = parse_url($url);
        if (!$parsedUrl) {
            return $url;
        }
        
        // Remove sensitive query parameters
        if (isset($parsedUrl['query'])) {
            $queryParams = [];
            parse_str($parsedUrl['query'], $queryParams);
            
            // List of sensitive parameter names to redact
            $sensitiveParams = [
                'password', 'passwd', 'pwd', 'secret', 'key', 'token', 'auth', 
                'api_key', 'api_secret', 'access_token', 'refresh_token',
                'session', 'sessionid', 'sid', 'csrf', 'xsrf',
                'authorization', 'bearer', 'apikey', 'apisecret'
            ];
            
            foreach ($sensitiveParams as $param) {
                if (isset($queryParams[$param])) {
                    $queryParams[$param] = '[REDACTED]';
                }
            }
            
            $parsedUrl['query'] = http_build_query($queryParams);
        }
        
        // Rebuild URL without sensitive data
        $scheme = isset($parsedUrl['scheme']) ? $parsedUrl['scheme'] . '://' : '';
        $host = $parsedUrl['host'] ?? '';
        $port = isset($parsedUrl['port']) ? ':' . $parsedUrl['port'] : '';
        $path = $parsedUrl['path'] ?? '';
        $query = isset($parsedUrl['query']) ? '?' . $parsedUrl['query'] : '';
        $fragment = isset($parsedUrl['fragment']) ? '#' . $parsedUrl['fragment'] : '';
        
        return $scheme . $host . $port . $path . $query . $fragment;
    }
}

// Helper function for traced Guzzle HTTP requests
if (!function_exists('traced_guzzle_request')) {
    function traced_guzzle_request($client, $method, $url, $options = []) {
        $traceId = isset($GLOBALS['otel_trace_id']) ? $GLOBALS['otel_trace_id'] : bin2hex(random_bytes(16));
        $parentSpanId = isset($GLOBALS['otel_span_id']) ? $GLOBALS['otel_span_id'] : null;
        $spanId = bin2hex(random_bytes(8));
        $startTime = microtime(true);
        
        // Debug: Log HTTP client span context
        file_put_contents('/tmp/debug.log', "[traced_guzzle_request] HTTP Client traceId: {$traceId}, spanId: {$spanId}, parentSpanId: " . ($parentSpanId ?? 'null') . "\n", FILE_APPEND);
        
        try {
            // Add trace headers to the request
            $options['headers'] = array_merge($options['headers'] ?? [], [
                'X-Trace-Id' => $traceId,
                'X-Span-Id' => $spanId
            ]);
            
            $response = $client->request($method, $url, $options);
            $endTime = microtime(true);
            
            // Extract URL components for attributes (sanitized)
            $parsedUrl = parse_url($url);
            $scheme = $parsedUrl['scheme'] ?? 'http';
            $host = $parsedUrl['host'] ?? '';
            $port = $parsedUrl['port'] ?? ($scheme === 'https' ? 443 : 80);
            $path = $parsedUrl['path'] ?? '/';
            
            // Sanitize URL for tracing
            $sanitizedUrl = sanitize_url_for_tracing($url);
            $sanitizedQuery = parse_url($sanitizedUrl, PHP_URL_QUERY);
            $query = $sanitizedQuery ? '?' . $sanitizedQuery : '';
            
            $attributes = [
                ['key' => 'http.request.method', 'value' => ['stringValue' => strtoupper($method)]],
                ['key' => 'url.scheme', 'value' => ['stringValue' => $scheme]],
                ['key' => 'url.path', 'value' => ['stringValue' => $path]],
                ['key' => 'url.query', 'value' => ['stringValue' => $query]],
                ['key' => 'url.full', 'value' => ['stringValue' => $sanitizedUrl]],
                ['key' => 'server.address', 'value' => ['stringValue' => $host]],
                ['key' => 'server.port', 'value' => ['intValue' => $port]],
                ['key' => 'http.response.status_code', 'value' => ['intValue' => $response->getStatusCode()]],
                ['key' => 'network.protocol.name', 'value' => ['stringValue' => 'http']],
                ['key' => 'network.protocol.version', 'value' => ['stringValue' => '1.1']],
            ];
            
            // Add request body size if available
            if (isset($options['json'])) {
                $attributes[] = ['key' => 'http.request.body.size', 'value' => ['intValue' => strlen(json_encode($options['json']))]];
            } elseif (isset($options['form_params'])) {
                $attributes[] = ['key' => 'http.request.body.size', 'value' => ['intValue' => strlen(http_build_query($options['form_params']))]];
            }
            
            // Add response body size if available
            $responseBody = $response->getBody()->getContents();
            if ($responseBody) {
                $attributes[] = ['key' => 'http.response.body.size', 'value' => ['intValue' => strlen($responseBody)]];
                // Reset the body stream position for future reads
                $response->getBody()->rewind();
            }
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'HTTP ' . strtoupper($method),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => $response->getStatusCode() >= 400 ? 2 : 1,
                    'message' => $response->getStatusCode() >= 400 ? 'HTTP ' . $response->getStatusCode() : null
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            return $response;
            
        } catch (Exception $e) {
            $endTime = microtime(true);
            
            // Extract URL components for attributes (sanitized)
            $parsedUrl = parse_url($url);
            $scheme = $parsedUrl['scheme'] ?? 'http';
            $host = $parsedUrl['host'] ?? '';
            $port = $parsedUrl['port'] ?? ($scheme === 'https' ? 443 : 80);
            $path = $parsedUrl['path'] ?? '/';
            
            // Sanitize URL for tracing
            $sanitizedUrl = sanitize_url_for_tracing($url);
            $sanitizedQuery = parse_url($sanitizedUrl, PHP_URL_QUERY);
            $query = $sanitizedQuery ? '?' . $sanitizedQuery : '';
            
            $attributes = [
                ['key' => 'http.request.method', 'value' => ['stringValue' => strtoupper($method)]],
                ['key' => 'url.scheme', 'value' => ['stringValue' => $scheme]],
                ['key' => 'url.path', 'value' => ['stringValue' => $path]],
                ['key' => 'url.query', 'value' => ['stringValue' => $query]],
                ['key' => 'url.full', 'value' => ['stringValue' => $sanitizedUrl]],
                ['key' => 'server.address', 'value' => ['stringValue' => $host]],
                ['key' => 'server.port', 'value' => ['intValue' => $port]],
                ['key' => 'network.protocol.name', 'value' => ['stringValue' => 'http']],
                ['key' => 'network.protocol.version', 'value' => ['stringValue' => '1.1']],
                ['key' => 'exception.type', 'value' => ['stringValue' => get_class($e)]],
                ['key' => 'exception.message', 'value' => ['stringValue' => $e->getMessage()]],
            ];
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'HTTP ' . strtoupper($method),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => 2, // ERROR
                    'message' => $e->getMessage()
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            throw $e;
        }
    }
}

// Helper function for traced cURL requests
if (!function_exists('traced_curl_exec')) {
    function traced_curl_exec($ch) {
        $traceId = isset($GLOBALS['otel_trace_id']) ? $GLOBALS['otel_trace_id'] : bin2hex(random_bytes(16));
        $parentSpanId = isset($GLOBALS['otel_span_id']) ? $GLOBALS['otel_span_id'] : null;
        $spanId = bin2hex(random_bytes(8));
        $startTime = microtime(true);
        
        // Debug: Log cURL span context
        file_put_contents('/tmp/debug.log', "[traced_curl_exec] cURL traceId: {$traceId}, spanId: {$spanId}, parentSpanId: " . ($parentSpanId ?? 'null') . "\n", FILE_APPEND);
        
        try {
            // Get URL from cURL handle
            $url = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
            $method = 'GET'; // Default method
            
            // Try to determine HTTP method from cURL options
            // Note: CURLINFO_CUSTOMREQUEST is not available in PHP 7.4, so we'll use a different approach
            $method = 'GET'; // Default method
            // We could try to infer from other cURL options, but for now we'll use GET as default
            
            // Add trace headers to the request
            $currentHeaders = curl_getinfo($ch, CURLINFO_HEADER_OUT);
            $traceHeaders = [
                'X-Trace-Id: ' . $traceId,
                'X-Span-Id: ' . $spanId
            ];
            
            // Execute the cURL request
            $result = curl_exec($ch);
            $endTime = microtime(true);
            
            // Get response information
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $totalTime = curl_getinfo($ch, CURLINFO_TOTAL_TIME);
            $sizeDownload = curl_getinfo($ch, CURLINFO_SIZE_DOWNLOAD);
            $sizeUpload = curl_getinfo($ch, CURLINFO_SIZE_UPLOAD);
            
            // Extract URL components for attributes (sanitized)
            $parsedUrl = parse_url($url);
            $scheme = $parsedUrl['scheme'] ?? 'http';
            $host = $parsedUrl['host'] ?? '';
            $port = $parsedUrl['port'] ?? ($scheme === 'https' ? 443 : 80);
            $path = $parsedUrl['path'] ?? '/';
            
            // Sanitize URL for tracing
            $sanitizedUrl = sanitize_url_for_tracing($url);
            $sanitizedQuery = parse_url($sanitizedUrl, PHP_URL_QUERY);
            $query = $sanitizedQuery ? '?' . $sanitizedQuery : '';
            
            $attributes = [
                ['key' => 'http.request.method', 'value' => ['stringValue' => strtoupper($method)]],
                ['key' => 'url.scheme', 'value' => ['stringValue' => $scheme]],
                ['key' => 'url.path', 'value' => ['stringValue' => $path]],
                ['key' => 'url.query', 'value' => ['stringValue' => $query]],
                ['key' => 'url.full', 'value' => ['stringValue' => $sanitizedUrl]],
                ['key' => 'server.address', 'value' => ['stringValue' => $host]],
                ['key' => 'server.port', 'value' => ['intValue' => $port]],
                ['key' => 'http.response.status_code', 'value' => ['intValue' => $httpCode]],
                ['key' => 'network.protocol.name', 'value' => ['stringValue' => 'http']],
                ['key' => 'network.protocol.version', 'value' => ['stringValue' => '1.1']],
            ];
            
            // Add timing information
            if ($totalTime > 0) {
                $attributes[] = ['key' => 'http.request.duration', 'value' => ['stringValue' => (string)($totalTime * 1000)]];
            }
            
            // Add size information
            if ($sizeDownload > 0) {
                $attributes[] = ['key' => 'http.response.body.size', 'value' => ['intValue' => $sizeDownload]];
            }
            if ($sizeUpload > 0) {
                $attributes[] = ['key' => 'http.request.body.size', 'value' => ['intValue' => $sizeUpload]];
            }
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'HTTP ' . strtoupper($method),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => ($httpCode >= 400 || $result === false) ? 2 : 1,
                    'message' => ($httpCode >= 400 || $result === false) ? 'HTTP ' . $httpCode : null
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            return $result;
            
        } catch (Exception $e) {
            $endTime = microtime(true);
            
            // Extract URL components for attributes (sanitized)
            $parsedUrl = parse_url($url ?? '');
            $scheme = $parsedUrl['scheme'] ?? 'http';
            $host = $parsedUrl['host'] ?? '';
            $port = $parsedUrl['port'] ?? ($scheme === 'https' ? 443 : 80);
            $path = $parsedUrl['path'] ?? '/';
            
            // Sanitize URL for tracing
            $sanitizedUrl = sanitize_url_for_tracing($url ?? '');
            $sanitizedQuery = parse_url($sanitizedUrl, PHP_URL_QUERY);
            $query = $sanitizedQuery ? '?' . $sanitizedQuery : '';
            
            $attributes = [
                ['key' => 'http.request.method', 'value' => ['stringValue' => strtoupper($method ?? 'GET')]],
                ['key' => 'url.scheme', 'value' => ['stringValue' => $scheme]],
                ['key' => 'url.path', 'value' => ['stringValue' => $path]],
                ['key' => 'url.query', 'value' => ['stringValue' => $query]],
                ['key' => 'url.full', 'value' => ['stringValue' => $sanitizedUrl]],
                ['key' => 'server.address', 'value' => ['stringValue' => $host]],
                ['key' => 'server.port', 'value' => ['intValue' => $port]],
                ['key' => 'network.protocol.name', 'value' => ['stringValue' => 'http']],
                ['key' => 'network.protocol.version', 'value' => ['stringValue' => '1.1']],
                ['key' => 'exception.type', 'value' => ['stringValue' => get_class($e)]],
                ['key' => 'exception.message', 'value' => ['stringValue' => $e->getMessage()]],
            ];
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'HTTP ' . strtoupper($method ?? 'GET'),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => 2, // ERROR
                    'message' => $e->getMessage()
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            throw $e;
        }
    }
}

// Helper function for traced PDO queries
if (!function_exists('traced_pdo_query')) {
    function traced_pdo_query($pdo, $query) {
        $traceId = isset($GLOBALS['otel_trace_id']) ? $GLOBALS['otel_trace_id'] : bin2hex(random_bytes(16));
        $parentSpanId = isset($GLOBALS['otel_span_id']) ? $GLOBALS['otel_span_id'] : null;
        $spanId = bin2hex(random_bytes(8));
        $startTime = microtime(true);
        
        // Debug: Log PDO query span context
        file_put_contents('/tmp/debug.log', "[traced_pdo_query] PDO Query traceId: {$traceId}, spanId: {$spanId}, parentSpanId: " . ($parentSpanId ?? 'null') . "\n", FILE_APPEND);
        
        try {
            $result = $pdo->query($query);
            $endTime = microtime(true);
            
            // Extract database operation and table name
            $operation = extractDbOperation($query);
            $tableName = extractTableName($query, $operation);
            
            $attributes = [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                ['key' => 'db.operation', 'value' => ['stringValue' => $operation]],
                ['key' => 'db.name', 'value' => ['stringValue' => $_ENV['DB_DATABASE'] ?? 'laravel']],
                ['key' => 'server.address', 'value' => ['stringValue' => $_ENV['DB_HOST'] ?? 'mysql']],
                ['key' => 'server.port', 'value' => ['intValue' => (int)($_ENV['DB_PORT'] ?? 3306)]],
                ['key' => 'network.transport', 'value' => ['stringValue' => 'tcp']],
                ['key' => 'network.type', 'value' => ['stringValue' => 'ipv4']],
                ['key' => 'db.user', 'value' => ['stringValue' => $_ENV['DB_USERNAME'] ?? 'root']],
            ];
            
            if ($tableName) {
                $attributes[] = ['key' => 'db.sql.table', 'value' => ['stringValue' => $tableName]];
            }
            
            // Add row count if available
            if ($result && method_exists($result, 'rowCount')) {
                $rowCount = $result->rowCount();
                if ($rowCount >= 0) {
                    $attributes[] = ['key' => 'db.rows_affected', 'value' => ['intValue' => $rowCount]];
                }
            }
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'db.' . $operation . ($tableName ? " {$tableName}" : ''),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => 1, // OK
                    'message' => null
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            return $result;
            
        } catch (Exception $e) {
            $endTime = microtime(true);
            
            // Extract database operation and table name
            $operation = extractDbOperation($query);
            $tableName = extractTableName($query, $operation);
            
            $attributes = [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                ['key' => 'db.operation', 'value' => ['stringValue' => $operation]],
                ['key' => 'db.name', 'value' => ['stringValue' => $_ENV['DB_DATABASE'] ?? 'laravel']],
                ['key' => 'server.address', 'value' => ['stringValue' => $_ENV['DB_HOST'] ?? 'mysql']],
                ['key' => 'server.port', 'value' => ['intValue' => (int)($_ENV['DB_PORT'] ?? 3306)]],
                ['key' => 'network.transport', 'value' => ['stringValue' => 'tcp']],
                ['key' => 'network.type', 'value' => ['stringValue' => 'ipv4']],
                ['key' => 'db.user', 'value' => ['stringValue' => $_ENV['DB_USERNAME'] ?? 'root']],
                ['key' => 'exception.type', 'value' => ['stringValue' => get_class($e)]],
                ['key' => 'exception.message', 'value' => ['stringValue' => $e->getMessage()]],
            ];
            
            if ($tableName) {
                $attributes[] = ['key' => 'db.sql.table', 'value' => ['stringValue' => $tableName]];
            }
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'db.' . $operation . ($tableName ? " {$tableName}" : ''),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => 2, // ERROR
                    'message' => $e->getMessage()
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            throw $e;
        }
    }
}

// Helper function for traced PDO prepared statements
if (!function_exists('traced_pdo_prepare')) {
    function traced_pdo_prepare($pdo, $query) {
        $traceId = isset($GLOBALS['otel_trace_id']) ? $GLOBALS['otel_trace_id'] : bin2hex(random_bytes(16));
        $parentSpanId = isset($GLOBALS['otel_span_id']) ? $GLOBALS['otel_span_id'] : null;
        $spanId = bin2hex(random_bytes(8));
        $startTime = microtime(true);
        
        // Debug: Log PDO prepare span context
        file_put_contents('/tmp/debug.log', "[traced_pdo_prepare] PDO Prepare traceId: {$traceId}, spanId: {$spanId}, parentSpanId: " . ($parentSpanId ?? 'null') . "\n", FILE_APPEND);
        
        try {
            $stmt = $pdo->prepare($query);
            $endTime = microtime(true);
            
            // Extract database operation and table name
            $operation = extractDbOperation($query);
            $tableName = extractTableName($query, $operation);
            
            $attributes = [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                ['key' => 'db.operation', 'value' => ['stringValue' => $operation]],
                ['key' => 'db.name', 'value' => ['stringValue' => $_ENV['DB_DATABASE'] ?? 'laravel']],
                ['key' => 'server.address', 'value' => ['stringValue' => $_ENV['DB_HOST'] ?? 'mysql']],
                ['key' => 'server.port', 'value' => ['intValue' => (int)($_ENV['DB_PORT'] ?? 3306)]],
                ['key' => 'network.transport', 'value' => ['stringValue' => 'tcp']],
                ['key' => 'network.type', 'value' => ['stringValue' => 'ipv4']],
                ['key' => 'db.user', 'value' => ['stringValue' => $_ENV['DB_USERNAME'] ?? 'root']],
            ];
            
            if ($tableName) {
                $attributes[] = ['key' => 'db.sql.table', 'value' => ['stringValue' => $tableName]];
            }
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'db.prepare.' . $operation . ($tableName ? " {$tableName}" : ''),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => 1, // OK
                    'message' => null
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            return $stmt;
            
        } catch (Exception $e) {
            $endTime = microtime(true);
            
            // Extract database operation and table name
            $operation = extractDbOperation($query);
            $tableName = extractTableName($query, $operation);
            
            $attributes = [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                ['key' => 'db.operation', 'value' => ['stringValue' => $operation]],
                ['key' => 'db.name', 'value' => ['stringValue' => $_ENV['DB_DATABASE'] ?? 'laravel']],
                ['key' => 'server.address', 'value' => ['stringValue' => $_ENV['DB_HOST'] ?? 'mysql']],
                ['key' => 'server.port', 'value' => ['intValue' => (int)($_ENV['DB_PORT'] ?? 3306)]],
                ['key' => 'network.transport', 'value' => ['stringValue' => 'tcp']],
                ['key' => 'network.type', 'value' => ['stringValue' => 'ipv4']],
                ['key' => 'db.user', 'value' => ['stringValue' => $_ENV['DB_USERNAME'] ?? 'root']],
                ['key' => 'exception.type', 'value' => ['stringValue' => get_class($e)]],
                ['key' => 'exception.message', 'value' => ['stringValue' => $e->getMessage()]],
            ];
            
            if ($tableName) {
                $attributes[] = ['key' => 'db.sql.table', 'value' => ['stringValue' => $tableName]];
            }
            
            $span = [
                'traceId' => $traceId,
                'spanId' => $spanId,
                'name' => 'db.prepare.' . $operation . ($tableName ? " {$tableName}" : ''),
                'kind' => 3, // CLIENT
                'startTime' => $startTime,
                'endTime' => $endTime,
                'attributes' => $attributes,
                'status' => [
                    'code' => 2, // ERROR
                    'message' => $e->getMessage()
                ]
            ];
            
            if ($parentSpanId) {
                $span['parentSpanId'] = $parentSpanId;
            }
            
            $GLOBALS['manual_tracer']->finishSpan($span, $span['status']['code'], $span['status']['message']);
            
            throw $e;
        }
    }
}

// Helper functions for database operation extraction
if (!function_exists('extractDbOperation')) {
    function extractDbOperation($query) {
        $query = trim(strtoupper($query));
        if (preg_match('/^(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE|REPLACE|SHOW|DESCRIBE|EXPLAIN)/', $query, $matches)) {
            return strtolower($matches[1]);
        }
        return 'query';
    }
}

if (!function_exists('extractTableName')) {
    function extractTableName($query, $operation) {
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
}

// OpenTelemetry manual instrumentation initialized