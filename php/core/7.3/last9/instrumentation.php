<?php
namespace Last9;

use GuzzleHttp\Client;

require_once __DIR__ . '/instrumentMySQLi.php';
require_once __DIR__ . '/instrumentHttpClient.php';

// After other aliases
if (!class_exists('\mysqli')) {
    error_log("[MySQLi Debug] Aliasing MySQLi class");
    class_alias('\Last9\InstrumentedMySQLi', '\mysqli');
} else {
    error_log("[MySQLi Debug] MySQLi class already exists");
}

define('OTLP_COLLECTOR_URL', getenv('OTEL_EXPORTER_OTLP_ENDPOINT') . '/v1/traces');

function createSpan($name, $parentSpanId = null, $attributes = []) {
    $spanId = bin2hex(random_bytes(8));
    $timestamp = (int)(microtime(true) * 1e6);
    
    $span = [
        'traceId' => Instrumentation::$traceId,
        'spanId' => $spanId,
        'parentSpanId' => $parentSpanId,
        'name' => $name,
        'kind' => 2, // Server
        'startTimeUnixNano' => $timestamp * 1000,
        'endTimeUnixNano' => null,
        'attributes' => $attributes,
        'status' => ['code' => 1]
    ];
    
    return ['span' => $span, 'startTime' => $timestamp];
}

function endSpan(&$spanData, $status = ['code' => 1], $additionalAttributes = [], $events = []) {
    $endTime = (int)(microtime(true) * 1e6);
    $spanData['span']['endTimeUnixNano'] = $endTime * 1000;
    $spanData['span']['status'] = $status;
    $spanData['span']['attributes'] = array_merge(
        $spanData['span']['attributes'], 
        $additionalAttributes
    );
    
    // Add events if any
    if (!empty($events)) {
        $spanData['span']['events'] = $events;
    }
    
    Instrumentation::addSpan($spanData['span']);
    return $spanData;
}

class Instrumentation {
    public static $traceId = null;
    private static $spans = [];
    private static $rootSpan = null;
    private static $parentSpanId = null;

    private static function extractTraceContext() {
        $headers = getallheaders();
        if (isset($headers['traceparent'])) {
            // traceparent format: 00-<trace-id>-<parent-id>-<trace-flags>
            $parts = explode('-', $headers['traceparent']);
            if (count($parts) === 4) {
                self::$traceId = $parts[1];
                self::$parentSpanId = $parts[2];
                return true;
            }
        }
        return false;
    }

    public static function getRootSpanId() {
        return self::$rootSpan['span']['spanId'] ?? null;
    }

    public static function addSpan($span) {
        self::$spans[] = $span;
    }

    public static function autoInit() {
        if (self::$rootSpan === null) {
            $uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
            $method = $_SERVER['REQUEST_METHOD'];
            
            // Extract trace context or generate new if not found
            if (!self::extractTraceContext()) {
                self::$traceId = bin2hex(random_bytes(16));
            }
            
            self::$spans = [];
            self::$rootSpan = self::createRootSpan("$method $uri");
            
            // Set parent span ID if it exists
            if (self::$parentSpanId) {
                self::$rootSpan['span']['parentSpanId'] = self::$parentSpanId;
            }
        }
        return self::$rootSpan;
    }

    private static function createRootSpan($name) {
        $spanData = createSpan($name);
        
        $httpAttributes = [
            ['key' => 'http.method', 'value' => ['stringValue' => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN']],
            ['key' => 'http.target', 'value' => ['stringValue' => $_SERVER['REQUEST_URI'] ?? '']],
            ['key' => 'http.host', 'value' => ['stringValue' => $_SERVER['HTTP_HOST'] ?? '']],
            ['key' => 'http.scheme', 'value' => ['stringValue' => isset($_SERVER['HTTPS']) ? 'https' : 'http']],
            ['key' => 'http.status_code', 'value' => ['intValue' => (int)http_response_code()]],
            ['key' => 'http.user_agent', 'value' => ['stringValue' => $_SERVER['HTTP_USER_AGENT'] ?? '']],
            ['key' => 'net.peer.ip', 'value' => ['stringValue' => $_SERVER['REMOTE_ADDR'] ?? '']]
        ];
        
        $spanData['span']['attributes'] = $httpAttributes;
        return $spanData;
    }

    public static function finish($status = ['code' => 1], $attributes = []) {
        if (self::$rootSpan) {
            endSpan(self::$rootSpan, $status, $attributes);
            self::sendTraces();
        }
    }

    private static function sendTraces() {
        $tracePayload = [
            'resourceSpans' => [
                [
                    'resource' => [
                        'attributes' => [
                            ['key' => 'service.name', 'value' => ['stringValue' => 'demo-service']],
                            ['key' => 'deployment.environment', 'value' => ['stringValue' => 'production']],
                            ['key' => 'host.name', 'value' => ['stringValue' => gethostname()]],
                            ['key' => 'os.type', 'value' => ['stringValue' => PHP_OS]],
                            ['key' => 'process.runtime.name', 'value' => ['stringValue' => 'php']],
                            ['key' => 'process.runtime.version', 'value' => ['stringValue' => PHP_VERSION]]
                        ]
                    ],
                    'scopeSpans' => [
                        [
                            'spans' => self::$spans
                        ]
                    ]
                ]
            ]
        ];

        try {
            if (function_exists('fastcgi_finish_request')) {
                fastcgi_finish_request();
            }
            
            ignore_user_abort(true);
            set_time_limit(0);
            
            $client = new Client([
                'timeout' => 5,
                'connect_timeout' => 2
            ]);

            // error_log("[OpenTelemetry] Trace payload: " . json_encode($tracePayload));
            
            $response = $client->post(OTLP_COLLECTOR_URL, [
                'json' => $tracePayload,
                'headers' => [
                    'Content-Type' => 'application/json',
                    'Authorization' => getenv('OTEL_EXPORTER_OTLP_HEADERS')
                ]
            ]);
            
            error_log("[OpenTelemetry] Traces sent successfully: " . count(self::$spans) . " spans");
            return true;
        } catch (\Exception $e) {
            error_log("[OpenTelemetry] Failed to send traces: " . $e->getMessage());
            return false;
        }
    }
}

// Auto-initialize instrumentation
Instrumentation::autoInit();

// Register shutdown function
register_shutdown_function(function() {
    $error = error_get_last();
    $httpCode = http_response_code();
    
    if ($error !== null && in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        // PHP Error occurred
        Instrumentation::finish(
            ['code' => 2, 'message' => $error['message']],
            [['key' => 'error.message', 'value' => ['stringValue' => $error['message']]]],
            [ // Add events array for error
                [
                    'name' => 'exception',
                    'timeUnixNano' => (int)(microtime(true) * 1e9),
                    'attributes' => [
                        ['key' => 'exception.type', 'value' => ['stringValue' => 'PHPError']],
                        ['key' => 'exception.message', 'value' => ['stringValue' => $error['message']]],
                        ['key' => 'exception.file', 'value' => ['stringValue' => $error['file']]],
                        ['key' => 'exception.line', 'value' => ['intValue' => $error['line']]]
                    ]
                ]
            ]
        );
    } elseif ($httpCode >= 400) {
        // HTTP error occurred (4xx or 5xx)
        Instrumentation::finish(
            ['code' => 2, 'message' => 'HTTP ' . $httpCode],
            [
                ['key' => 'error.type', 'value' => ['stringValue' => 'HTTPError']],
                ['key' => 'http.status_code', 'value' => ['intValue' => (int)$httpCode]]
            ],
            [ // Add events array for error
                [
                    'name' => 'exception',
                    'timeUnixNano' => (int)(microtime(true) * 1e9),
                    'attributes' => [
                        ['key' => 'exception.type', 'value' => ['stringValue' => 'HTTPError']],
                        ['key' => 'exception.message', 'value' => ['stringValue' => 'HTTP ' . $httpCode]],
                        ['key' => 'http.status_code', 'value' => ['intValue' => (int)$httpCode]]
                    ]
                ]
            ]
        );
    } else {
        // Success case
        Instrumentation::finish(
            ['code' => 1],
            [['key' => 'http.status_code', 'value' => ['intValue' => (int)$httpCode]]]
        );
    }
});
