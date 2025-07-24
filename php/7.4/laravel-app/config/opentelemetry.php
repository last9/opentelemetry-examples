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
    
    /*
    |--------------------------------------------------------------------------
    | Batch Span Processor Configuration (OpenTelemetry SDK Defaults)
    |--------------------------------------------------------------------------
    |
    | Configuration following OpenTelemetry SDK batch span processor defaults.
    | These settings match the official OpenTelemetry SDK specifications.
    |
    */
    
    'batch_span_processor' => [
        // Maximum number of spans to batch before sending (OpenTelemetry SDK default: 2048)
        'max_export_batch_size' => env('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', 2048),
        
        // Maximum number of spans to queue (OpenTelemetry SDK default: 2048)
        'max_queue_size' => env('OTEL_BSP_MAX_QUEUE_SIZE', 2048),
        
        // Scheduled delay in milliseconds (OpenTelemetry SDK default: 5000ms)
        'scheduled_delay_ms' => env('OTEL_BSP_SCHEDULED_DELAY_MS', 5000),
        
        // Export timeout in milliseconds (OpenTelemetry SDK default: 30000ms)
        'export_timeout_ms' => env('OTEL_BSP_EXPORT_TIMEOUT_MS', 30000),
        
        // Maximum time to wait for spans to be processed (OpenTelemetry SDK default: 30000ms)
        'max_concurrent_exports' => env('OTEL_BSP_MAX_CONCURRENT_EXPORTS', 1),
    ],
    
    /*
    |--------------------------------------------------------------------------
    | Legacy Optimization Configuration (Deprecated)
    |--------------------------------------------------------------------------
    |
    | These settings are kept for backward compatibility but should be replaced
    | with the batch_span_processor settings above.
    |
    */
    
    'optimization' => [
        // Number of traces to batch before sending (legacy - use max_export_batch_size instead)
        'batch_size' => env('OTEL_BATCH_SIZE', 2048),
        
        // Time interval in seconds to flush traces (legacy - use scheduled_delay_ms instead)
        'flush_interval' => env('OTEL_FLUSH_INTERVAL', 5),
        
        // HTTP timeout for export requests (legacy - use export_timeout_ms instead)
        'export_timeout' => env('OTEL_EXPORT_TIMEOUT', 30.0),
        
        // HTTP connection timeout (seconds)
        'connect_timeout' => env('OTEL_CONNECT_TIMEOUT', 1.0),
        
        // Enable async export (recommended for production)
        'async_export' => env('OTEL_ASYNC_EXPORT', true),
        
        // Enable batching (recommended for production)
        'enable_batching' => env('OTEL_ENABLE_BATCHING', true),
    ],
]; 