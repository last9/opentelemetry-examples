<?php

namespace App\Http\Middleware;

use Closure;
use GuzzleHttp\Client;
use Exception;

class OpenTelemetryMiddleware
{
    private $client;
    
    public function __construct()
    {
        $this->client = new Client([
            'timeout' => 1.0,
            'verify' => false
        ]);
    }

    public function handle($request, Closure $next)
    {
        $traceId = bin2hex(random_bytes(16));
        $spanId = bin2hex(random_bytes(8));
        $startTime = microtime(true);
        
        // Store trace info in request for potential child spans
        $request->attributes->set('trace_id', $traceId);
        $request->attributes->set('span_id', $spanId);
        // Store in globals for DB/curl spans
        $GLOBALS['otel_trace_id'] = $traceId;
        $GLOBALS['otel_span_id'] = $spanId;

        
        try {
            $response = $next($request);
            $endTime = microtime(true);
            
            // Send trace data to collector
            $this->sendTrace($traceId, $spanId, $startTime, $endTime, $request, $response);
            
            return $response;
        } catch (Exception $e) {
            $endTime = microtime(true);
            $this->sendTrace($traceId, $spanId, $startTime, $endTime, $request, null, $e);
            throw $e;
        }
    }
    
    private function sendTrace($traceId, $spanId, $startTime, $endTime, $request, $response = null, $exception = null)
    {
        // Standard OpenTelemetry HTTP Server span attributes
        $attributes = [
            // Required attributes for HTTP server spans
            ['key' => 'http.request.method', 'value' => ['stringValue' => $request->method()]],
            ['key' => 'url.scheme', 'value' => ['stringValue' => $request->getScheme()]],
            ['key' => 'url.path', 'value' => ['stringValue' => $request->getPathInfo()]],
            ['key' => 'server.address', 'value' => ['stringValue' => $request->getHost()]],
            ['key' => 'server.port', 'value' => ['intValue' => $request->getPort()]],
            
            // Additional recommended attributes
            ['key' => 'user_agent.original', 'value' => ['stringValue' => $request->userAgent() ?? '']],
            ['key' => 'client.address', 'value' => ['stringValue' => $request->getClientIp() ?? '']],
            ['key' => 'network.protocol.version', 'value' => ['stringValue' => $request->server('SERVER_PROTOCOL', 'HTTP/1.1')]],
        ];
        
        // Add route pattern if available (Laravel specific)
        if ($request->route()) {
            $attributes[] = ['key' => 'http.route', 'value' => ['stringValue' => $request->route()->uri()]];
        }
        
        // Add query string if present (sanitized)
        if ($request->getQueryString()) {
            $queryString = $request->getQueryString();
            // Sanitize query string to remove sensitive parameters
            $queryParams = [];
            parse_str($queryString, $queryParams);
            
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
            
            $sanitizedQueryString = http_build_query($queryParams);
            $attributes[] = ['key' => 'url.query', 'value' => ['stringValue' => $sanitizedQueryString]];
        }
        
        // Add full URL for reference (sanitized)
        $fullUrl = $request->fullUrl();
        if ($request->getQueryString()) {
            $queryParams = [];
            parse_str($request->getQueryString(), $queryParams);
            
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
            
            $sanitizedQueryString = http_build_query($queryParams);
            $fullUrl = $request->url() . ($sanitizedQueryString ? '?' . $sanitizedQueryString : '');
        }
        
        $attributes[] = ['key' => 'url.full', 'value' => ['stringValue' => $fullUrl]];
        
        // Add request body size if available
        if ($request->header('Content-Length')) {
            $attributes[] = ['key' => 'http.request.body.size', 'value' => ['intValue' => (int)$request->header('Content-Length')]];
        }
        
        // Response attributes
        if ($response) {
            $attributes[] = ['key' => 'http.response.status_code', 'value' => ['intValue' => $response->getStatusCode()]];
            
            // Add response body size if available
            if ($response->headers->has('Content-Length')) {
                $attributes[] = ['key' => 'http.response.body.size', 'value' => ['intValue' => (int)$response->headers->get('Content-Length')]];
            }
        }
        
        // Error attributes following OpenTelemetry conventions
        if ($exception) {
            $attributes[] = ['key' => 'error.type', 'value' => ['stringValue' => get_class($exception)]];
            $attributes[] = ['key' => 'error.message', 'value' => ['stringValue' => $exception->getMessage()]];
            
            // Add exception stack trace for debugging (optional)
            $attributes[] = ['key' => 'exception.stacktrace', 'value' => ['stringValue' => $exception->getTraceAsString()]];
        }
        
        $traceData = [
            'resourceSpans' => [
                [
                    'resource' => [
                        'attributes' => [
                            // Required service attributes
                            ['key' => 'service.name', 'value' => ['stringValue' => $_ENV['OTEL_SERVICE_NAME'] ?? 'laravel-app']],
                            ['key' => 'service.version', 'value' => ['stringValue' => $_ENV['OTEL_SERVICE_VERSION'] ?? '1.0.0']],
                            ['key' => 'service.instance.id', 'value' => ['stringValue' => gethostname() . '-' . getmypid()]],
                            
                            // Environment and deployment attributes
                            ['key' => 'deployment.environment', 'value' => ['stringValue' => app()->environment()]],
                            
                            // Runtime attributes
                            ['key' => 'process.runtime.name', 'value' => ['stringValue' => 'php']],
                            ['key' => 'process.runtime.version', 'value' => ['stringValue' => PHP_VERSION]],
                            ['key' => 'process.pid', 'value' => ['intValue' => getmypid()]],
                            
                            // Telemetry attributes
                            ['key' => 'telemetry.sdk.name', 'value' => ['stringValue' => 'opentelemetry-php-manual']],
                            ['key' => 'telemetry.sdk.version', 'value' => ['stringValue' => '1.0.0']],
                            ['key' => 'telemetry.sdk.language', 'value' => ['stringValue' => 'php']],
                        ]
                    ],
                    'scopeSpans' => [
                        [
                            'scope' => ['name' => 'laravel-manual-tracer', 'version' => '1.0.0'],
                            'spans' => [
                                [
                                    'traceId' => $traceId,
                                    'spanId' => $spanId,
                                    'name' => $this->generateSpanName($request),
                                    'kind' => 2, // SERVER (SpanKind.SERVER)
                                    'startTimeUnixNano' => (int)($startTime * 1_000_000_000),
                                    'endTimeUnixNano' => (int)($endTime * 1_000_000_000),
                                    'attributes' => $attributes,
                                    'status' => $this->getSpanStatus($response, $exception)
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ];
        
        // Send to collector
        try {
            $url = env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT') ?? 'http://localhost:4318/v1/traces';
            $headers = ['Content-Type' => 'application/json'];
            // Parse OTEL_EXPORTER_OTLP_HEADERS if set
            if (!empty(env('OTEL_EXPORTER_OTLP_HEADERS'))) {
                $headerPairs = explode(',', env('OTEL_EXPORTER_OTLP_HEADERS'));
                foreach ($headerPairs as $pair) {
                    $kv = explode('=', $pair, 2);
                    if (count($kv) === 2) {
                        $key = urldecode(trim($kv[0]));
                        $value = urldecode(trim($kv[1]));
                        $headers[$key] = $value;
                    }
                }
            }
            $this->client->post($url, [
                'json' => $traceData,
                'headers' => $headers
            ]);
        } catch (Exception $e) {
            // Log errors but don't break the application
            error_log("OpenTelemetry trace sending failed: " . $e->getMessage());
        }
    }
    
    /**
     * Generate span name following OpenTelemetry HTTP semantic conventions
     * Format: HTTP method + route pattern (if available) or path
     */
    private function generateSpanName($request)
    {
        $method = $request->method();
        
        // Use route pattern if available (e.g., "GET /users/{id}")
        if ($request->route()) {
            $routePattern = $request->route()->uri();
            return $method . ' ' . $routePattern;
        }
        
        // Fall back to path if no route pattern
        $path = $request->getPathInfo();
        return $method . ' ' . $path;
    }
    
    /**
     * Generate span status following OpenTelemetry conventions
     */
    private function getSpanStatus($response, $exception)
    {
        if ($exception) {
            return [
                'code' => 2, // STATUS_ERROR
                'message' => $exception->getMessage()
            ];
        }
        
        if ($response) {
            $statusCode = $response->getStatusCode();
            
            // HTTP status codes >= 400 are considered errors
            if ($statusCode >= 400) {
                return [
                    'code' => 2, // STATUS_ERROR
                    'message' => 'HTTP ' . $statusCode
                ];
            }
        }
        
        return [
            'code' => 1 // STATUS_OK
        ];
    }
}