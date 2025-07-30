<?php

return [
    /*
    |--------------------------------------------------------------------------
    | OpenTelemetry Route Tracing Configuration
    |--------------------------------------------------------------------------
    |
    | This array defines which route patterns should be traced by the
    | OpenTelemetry middleware. Routes starting with these patterns
    | will have tracing enabled.
    |
    | Examples:
    | - ['api'] - Only trace routes starting with /api
    | - ['api', 'admin'] - Trace routes starting with /api or /admin
    | - [''] - Trace all routes (empty string matches all)
    |
    */
    'traced_routes' => [
        'api'
    ],

    /*
    |--------------------------------------------------------------------------
    | Additional OpenTelemetry Configuration
    |--------------------------------------------------------------------------
    |
    | Additional configuration options for OpenTelemetry can be added here
    | as needed.
    |
    */
];