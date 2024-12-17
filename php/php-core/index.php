<?php
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Factory\AppFactory;
use GuzzleHttp\Client; // Use Guzzle for HTTP communication with OTLP collector

require __DIR__ . '/vendor/autoload.php';

// Replace with your OpenTelemetry collector endpoint
define('OTLP_COLLECTOR_URL', '<last9_otlp_endpoint>');

// Initialize Slim app
$app = AppFactory::create();

// Add routing middleware
$app->addRoutingMiddleware();

// Add error middleware
$errorMiddleware = $app->addErrorMiddleware(true, true, true);

// Function to create and send traces to the OpenTelemetry collector
function sendTrace($operationName, $attributes = []) {
    $traceId = bin2hex(random_bytes(16)); // Generate a random trace ID
    $spanId = bin2hex(random_bytes(8));  // Generate a random span ID
    $timestamp = (int)(microtime(true) * 1e6); // Get current timestamp in microseconds

    $tracePayload = [
        "resourceSpans" => [
            [
                "resource" => [
                    "attributes" => [
                        ["key" => "service.name", "value" => ["stringValue" => "demo-service"]]
                    ]
                ],
                "scopeSpans" => [
                    [
                        "spans" => [
                            [
                                "traceId" => $traceId,
                                "spanId" => $spanId,
                                "name" => $operationName,
                                "startTimeUnixNano" => $timestamp * 1000,
                                "endTimeUnixNano" => ($timestamp + 1000) * 1000, // Simulate 1ms duration
                                "attributes" => array_map(function ($key, $value) {
                                    return ["key" => $key, "value" => ["stringValue" => $value]];
                                }, array_keys($attributes), $attributes)
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ];

    $client = new Client();
    $response = $client->post(OTLP_COLLECTOR_URL, [
        'json' => $tracePayload,
        'headers' => ['Content-Type' => 'application/json'],
        'headers' => ['Authorization' => '<last9_auth_header>']
    ]);

    return $response->getStatusCode();
}

// Define routes
$app->get('/', function (Request $request, Response $response) {
    $response->getBody()->write("Hello World!");
    return $response;
});

$app->get('/rolldice', function (Request $request, Response $response) {
    $operationName = 'roll-dice';
    $result = random_int(1, 6);

    // Simulate tracing
    sendTrace($operationName, ['result' => strval($result)]);

    $response->getBody()->write("Rolled dice result: $result");
    return $response;
});
// Run the application
$app->run();
