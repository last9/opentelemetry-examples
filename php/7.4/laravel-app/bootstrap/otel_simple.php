<?php

// Minimal performance-optimized tracer class without regex parsing
class SimpleTracer {
    private $tracer;
    private static $instance = null;
    
    public function __construct() {
        $this->tracer = $GLOBALS['otel_tracer'] ?? null;
    }
    
    public static function getInstance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    // Optimized method for creating spans with proper lifecycle management
    public function createSpan($name, $attributes = [], $spanKind = null) {
        if (!$this->tracer) {
            return new \OpenTelemetry\API\Trace\NoopSpan(\OpenTelemetry\API\Trace\SpanContext::getInvalid());
        }
        
        $spanBuilder = $this->tracer->spanBuilder($name);
        
        // Set span kind if provided, default to INTERNAL for manual instrumentation
        if ($spanKind !== null) {
            $spanBuilder->setSpanKind($spanKind);
        } else {
            $spanBuilder->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_INTERNAL);
        }
        
        // Add attributes efficiently
        foreach ($attributes as $key => $value) {
            $spanBuilder->setAttribute($key, $value);
        }
        
        // Start span and return it for proper lifecycle management
        return $spanBuilder->startSpan();
    }
    
    // Legacy method for backward compatibility but optimized
    public function createTrace($name, $attributes = []) {
        $span = $this->createSpan($name, $attributes);
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        $span->end();
    }
    
    // Minimal database tracing without regex parsing
    public function traceDatabase($query, $dbName = null, $connectionName = null, $duration = null, $rowCount = null, $error = null, $customSpanName = null) {
        if (!$this->tracer) {
            return;
        }
        
        // Simple span name without parsing
        $spanName = $customSpanName ?: 'db.query';
        
        $spanBuilder = $this->tracer->spanBuilder($spanName)
            ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
            ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, 'mysql')
            ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_NAME, $dbName ?? 'laravel')
            ->setAttribute('server.address', 'localhost')
            ->setAttribute('server.port', 3306);
        
        if ($rowCount !== null) {
            $spanBuilder->setAttribute('db.rows_affected', $rowCount);
        }
        
        $span = $spanBuilder->startSpan();
        
        if ($error) {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $error->getMessage());
            $span->recordException($error);
        } else {
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
        }
        
        $span->end();
    }
}