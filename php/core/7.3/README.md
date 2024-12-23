# PHP 7.3 Manual-Instrumentation with OpenTelemetry and Last9

This guide explains how to use Last9's OpenTelemetry traces endpoint to ingest PHP 7.3 application traces using OpenTelemetry Auto-Instrumentation.

## Prerequisites

- PHP 7.3
- Composer

## Setting up instrumentation

Create `instrumentation.php` file with the following content:
```
<?php
use GuzzleHttp\Client;

// Replace with your Last9 OpenTelemetry endpoint
define('OTLP_COLLECTOR_URL', '$last9_otlp_endpoint/v1/traces');

// Function to create and send traces to Last9
function instrumentHTTPRequest($operationName, $attributes = []) {
    $traceId = bin2hex(random_bytes(16));
    $spanId = bin2hex(random_bytes(8));
    $timestamp = (int)(microtime(true) * 1e6);

    $tracePayload = [
        "resourceSpans" => [
            [
                "resource" => [
                    "attributes" => [
                        ["key" => "service.name", "value" => ["stringValue" => "<service_name>"]],
                        ["key" => "deployment.environment", "value" => ["stringValue" => "<environment>"]],
                        ["key" => "host.name", "value" => ["stringValue" => gethostname()]],
                        ["key" => "os.type", "value" => ["stringValue" => PHP_OS]],
                        ["key" => "process.runtime.name", "value" => ["stringValue" => "php"]],
                        ["key" => "process.runtime.version", "value" => ["stringValue" => PHP_VERSION]]
                    ]
                ],
                "scopeSpans" => [
                    [
                        "spans" => [
                            [
                                "traceId" => $traceId,
                                "spanId" => $spanId,
                                "name" => $operationName,
                                "kind" => 2, // Server = 2 as per OTEL spec
                                "startTimeUnixNano" => $timestamp * 1000,
                                "endTimeUnixNano" => ($timestamp + 1000) * 1000,
                                "attributes" => array_merge(
                                    array_map(function ($key, $value) {
                                        return ["key" => $key, "value" => ["stringValue" => (string)$value]];
                                    }, array_keys($attributes), $attributes),
                                    [
                                        ["key" => "http.method", "value" => ["stringValue" => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN']],
                                        ["key" => "http.target", "value" => ["stringValue" => $_SERVER['REQUEST_URI'] ?? '']],
                                        ["key" => "http.host", "value" => ["stringValue" => $_SERVER['HTTP_HOST'] ?? '']],
                                        ["key" => "http.scheme", "value" => ["stringValue" => isset($_SERVER['HTTPS']) ? 'https' : 'http']],
                                        ["key" => "http.status_code", "value" => ["intValue" => http_response_code()]],
                                        ["key" => "http.response_content_length", "value" => ["intValue" => isset($response) ? strlen($response) : 0]],
                                        ["key" => "http.user_agent", "value" => ["stringValue" => $_SERVER['HTTP_USER_AGENT'] ?? '']],
                                        ["key" => "net.peer.ip", "value" => ["stringValue" => $_SERVER['REMOTE_ADDR'] ?? '']]
                                    ]
                                ),
                                "status" => [
                                    "code" => http_response_code() < 400 ? 1 : 2, // OK = 1, ERROR = 2
                                    "message" => http_response_code() >= 400 ? "HTTP " . http_response_code() : ""
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ];

    try {
        // Send the main response to the client first
        if (function_exists('fastcgi_finish_request')) {
            fastcgi_finish_request();
        }
        
        // Prevent the script from being terminated even if the client disconnects
        ignore_user_abort(true);
        
        // Set unlimited time for the background process
        set_time_limit(0);
        
        $client = new Client([
            'timeout' => 5, // Add a timeout to prevent hanging
            'connect_timeout' => 2
        ]);
        
        $response = $client->post(OTLP_COLLECTOR_URL, [
            'json' => $tracePayload,
            'headers' => [
                'Content-Type' => 'application/json',
                'Authorization' => 'Basic <$last9_otlp_header>')
            ]
        ]);
        
        error_log("[OpenTelemetry] Trace sent successfully: " . $operationName);
        return true;
    } catch (\Exception $e) {
        error_log("[OpenTelemetry] Failed to send trace: " . $e->getMessage());
        return false;
    }
}
```

Replace `<service_name>` and `<environment>` with your service name and environment.

## Instrumenting HTTP endpoints

For any endpoint that you want to instrument, you can call the `instrumentHTTPRequest` function with the operation name and attributes. All attributes are optional, but they will help you to filter traces in Last9. 

For example, if you want to instrument the `/rolldice` endpoint, you can call the `instrumentHTTPRequest` function with the operation name and attributes.

```
instrumentHTTPRequest('GET /rolldice', ['result' => strval($result)]);
```

Operation name is the HTTP method and path. You can standardize it as follows:

```
$method = $_SERVER['REQUEST_METHOD'];
$operationName = $method . ' ' . $uri;
```

## Visualizing traces in Last9

You can visualize traces in Last9 by going to the [Trace Explorer](https://app.last9.io/traces) and filtering by the operation name.