<?php

return [
    /*
    |--------------------------------------------------------------------------
    | OpenTelemetry Configuration - Official SDK Standards
    |--------------------------------------------------------------------------
    |
    | Configuration optimized for manual instrumentation performance using
    | official OpenTelemetry PHP SDK patterns and semantic conventions.
    |
    */

    'exporter' => [
        'endpoint' => env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'http://localhost:4318/v1/traces'),
        'headers' => env('OTEL_EXPORTER_OTLP_HEADERS', ''),
        'protocol' => env('OTEL_EXPORTER_OTLP_PROTOCOL', 'http/protobuf'),
        'compression' => env('OTEL_EXPORTER_OTLP_COMPRESSION', 'gzip'),
    ],

    'service' => [
        'name' => env('OTEL_SERVICE_NAME', 'laravel-app'),
        'version' => env('OTEL_SERVICE_VERSION', '1.0.0'),
        'environment' => env('OTEL_SERVICE_ENVIRONMENT', env('APP_ENV', 'local')),
    ],

    'enabled' => env('OTEL_ENABLED', true),
    
    /*
    |--------------------------------------------------------------------------
    | Performance-Optimized Batch Span Processor Configuration
    |--------------------------------------------------------------------------
    |
    | Optimized settings for high-performance manual instrumentation based on
    | official OpenTelemetry SDK specifications and best practices.
    |
    */
    
    'batch_span_processor' => [
        // Reduced batch size for faster export cycles
        'max_export_batch_size' => env('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', 512),
        
        // Larger queue size to handle bursts
        'max_queue_size' => env('OTEL_BSP_MAX_QUEUE_SIZE', 2048),
        
        // Faster export frequency for reduced latency
        'scheduled_delay_ms' => env('OTEL_BSP_SCHEDULED_DELAY_MS', 2000),
        
        // Reasonable timeout for network operations
        'export_timeout_ms' => env('OTEL_BSP_EXPORT_TIMEOUT_MS', 10000),
        
        // Single concurrent export to avoid resource contention
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