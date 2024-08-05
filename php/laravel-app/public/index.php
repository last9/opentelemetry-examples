<?php

use Illuminate\Http\Request;

// use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
// use OpenTelemetry\Contrib\Otlp\SpanExporter;
// use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
// use OpenTelemetry\SDK\Trace\TracerProvider;

define('LARAVEL_START', microtime(true));

// Determine if the application is in maintenance mode...
if (file_exists($maintenance = __DIR__.'/../storage/framework/maintenance.php')) {
    require $maintenance;
}


// Register the Composer autoloader...
require __DIR__.'/../vendor/autoload.php';

// $transport = (new OtlpHttpTransportFactory())->create(env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'), 'application/json', [ 'Authorization' => env('OTEL_EXPORTER_OTLP_AUTH_HEADER') ]);


// Bootstrap Laravel and handle the request...
(require_once __DIR__.'/../bootstrap/app.php')
    ->handleRequest(Request::capture());
