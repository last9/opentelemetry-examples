<?php

return [
    /*
    |--------------------------------------------------------------------------
    | OpenTelemetry Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for OpenTelemetry tracing and metrics collection.
    |
    */

    'exporter' => [
        'endpoint' => env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'http://localhost:4318/v1/traces'),
        'headers' => env('OTEL_EXPORTER_OTLP_HEADERS', ''),
    ],

    'service' => [
        'name' => env('OTEL_SERVICE_NAME', 'laravel-app'),
        'version' => env('OTEL_SERVICE_VERSION', '1.0.0'),
    ],

    'enabled' => env('OTEL_ENABLED', true),
]; 