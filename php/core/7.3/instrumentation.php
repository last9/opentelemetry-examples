<?php
use GuzzleHttp\Client;

define('OTLP_COLLECTOR_URL', 'https://$last9_otlp_endpoint/v1/traces');

// Global trace context
class TraceContext {
    private static $traceId = null;
    private static $spans = [];

    public static function init() {
        self::$traceId = bin2hex(random_bytes(16));
        self::$spans = [];
    }

    public static function getTraceId() {
        return self::$traceId;
    }

    public static function addSpan($span) {
        self::$spans[] = $span;
    }

    public static function getSpans() {
        return self::$spans;
    }
}

// Function to create a new span
function createSpan($name, $parentSpanId = null, $attributes = []) {
    $spanId = bin2hex(random_bytes(8));
    $timestamp = (int)(microtime(true) * 1e6);
    
    $span = [
        'traceId' => TraceContext::getTraceId(),
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

// Function to end a span
function endSpan(&$spanData, $status = ['code' => 1], $additionalAttributes = []) {
    $endTime = (int)(microtime(true) * 1e6);
    $spanData['span']['endTimeUnixNano'] = $endTime * 1000;
    $spanData['span']['status'] = $status;
    $spanData['span']['attributes'] = array_merge(
        $spanData['span']['attributes'], 
        $additionalAttributes
    );
    
    // Add the completed span to our trace context
    TraceContext::addSpan($spanData['span']);
    return $spanData;
}

// Function to instrument database queries
function instrumentDBQuery($query, $params = [], $parentSpanId = null) {
    $spanData = createSpan(
        'database.query',
        $parentSpanId,
        [
            ['key' => 'db.system', 'value' => ['stringValue' => 'mariadb']],
            ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
            ['key' => 'db.type', 'value' => ['stringValue' => 'sql']]
        ]
    );
    
    try {
        $pdo = new PDO(
            "mysql:host=" . getenv('DB_HOST') . ";dbname=" . getenv('DB_NAME'),
            getenv('DB_USER'),
            getenv('DB_PASSWORD')
        );
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        $stmt = $pdo->prepare($query);
        $result = $stmt->execute($params);
        
        endSpan($spanData, ['code' => 1]);
        return ['success' => true, 'result' => $stmt, 'span' => $spanData];
    } catch (PDOException $e) {
        endSpan($spanData, 
            ['code' => 2, 'message' => $e->getMessage()],
            [['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]]]
        );
        return ['success' => false, 'error' => $e->getMessage(), 'span' => $spanData];
    }
}

// Function to instrument HTTP client calls
function instrumentHTTPClient($method, $url, $options = [], $parentSpanId = null) {
    $spanData = createSpan(
        'http.client',
        $parentSpanId,
        [
            ['key' => 'http.method', 'value' => ['stringValue' => $method]],
            ['key' => 'http.url', 'value' => ['stringValue' => $url]]
        ]
    );
    
    try {
        $client = new Client(['timeout' => 5]);
        $response = $client->request($method, $url, $options);
        
        endSpan($spanData, 
            ['code' => 1],
            [['key' => 'http.status_code', 'value' => ['intValue' => $response->getStatusCode()]]]
        );
        
        return ['success' => true, 'response' => $response, 'span' => $spanData];
    } catch (\Exception $e) {
        endSpan($spanData, 
            ['code' => 2, 'message' => $e->getMessage()],
            [['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]]]
        );
        return ['success' => false, 'error' => $e->getMessage(), 'span' => $spanData];
    }
}

function instrumentHTTPRequest($operationName, $attributes = []) {
    // Initialize trace context for this request
    TraceContext::init();
    
    $spanData = createSpan($operationName);
    
    // Add HTTP request attributes
    $httpAttributes = [
        ['key' => 'http.method', 'value' => ['stringValue' => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN']],
        ['key' => 'http.target', 'value' => ['stringValue' => $_SERVER['REQUEST_URI'] ?? '']],
        ['key' => 'http.host', 'value' => ['stringValue' => $_SERVER['HTTP_HOST'] ?? '']],
        ['key' => 'http.scheme', 'value' => ['stringValue' => isset($_SERVER['HTTPS']) ? 'https' : 'http']],
        ['key' => 'http.status_code', 'value' => ['intValue' => http_response_code()]],
        ['key' => 'http.user_agent', 'value' => ['stringValue' => $_SERVER['HTTP_USER_AGENT'] ?? '']],
        ['key' => 'net.peer.ip', 'value' => ['stringValue' => $_SERVER['REMOTE_ADDR'] ?? '']]
    ];
    
    $spanData['span']['attributes'] = array_merge(
        array_map(function ($key, $value) {
            return ['key' => $key, 'value' => ['stringValue' => (string)$value]];
        }, array_keys($attributes), $attributes),
        $httpAttributes
    );
    
    return $spanData;
}

function sendTraces() {
    $spans = TraceContext::getSpans();
    
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
                        'spans' => $spans
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
        
        $response = $client->post(OTLP_COLLECTOR_URL, [
            'json' => $tracePayload,
            'headers' => [
                'Content-Type' => 'application/json',
                'Authorization' => 'Basic $last9_otlp_header'
            ]
        ]);
        
        error_log("[OpenTelemetry] Traces sent successfully: " . count($spans) . " spans");
        return true;
    } catch (\Exception $e) {
        error_log("[OpenTelemetry] Failed to send traces: " . $e->getMessage());
        return false;
    }
}