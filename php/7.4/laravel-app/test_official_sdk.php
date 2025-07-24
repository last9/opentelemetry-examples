<?php

/**
 * Test script demonstrating the official OpenTelemetry PHP SDK batch exporter logic
 * Based on: https://github.com/open-telemetry/opentelemetry-php/blob/9c3ae60164d1a6fb8a48f20c8a186cf3ef33813c/examples/traces/features/batch_exporting.php#L24
 */

require_once __DIR__ . '/vendor/autoload.php';

use OpenTelemetry\Contrib\Otlp\SpanExporterFactory;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProviderBuilder;
use OpenTelemetry\SDK\Common\Time\ClockFactory;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;

// Environment variables should be set in .env file or system environment
// The official SDK will use whatever is configured there

echo "🚀 Initializing Official OpenTelemetry PHP SDK...\n";

try {
    // Create the OTLP exporter using the official factory
    $exporterFactory = new SpanExporterFactory();
    $exporter = $exporterFactory->create();
    
    echo "✅ OTLP Exporter created successfully\n";
    
    // Create clock for batch processor
    $clock = ClockFactory::getDefault();
    
    // Create batch processor with official SDK defaults
    $batchProcessor = new BatchSpanProcessor(
        $exporter,
        $clock,
        2048,    // maxQueueSize
        5000,    // scheduledDelayMillis
        30000,   // exportTimeoutMillis
        512,     // maxExportBatchSize
        true     // autoFlush
    );
    
    echo "✅ BatchSpanProcessor created with configuration:\n";
    echo "   - Max Queue Size: 2048\n";
    echo "   - Scheduled Delay: 5000ms\n";
    echo "   - Export Timeout: 30000ms\n";
    echo "   - Max Export Batch Size: 512\n";
    echo "   - Auto Flush: true\n\n";
    
    // Create tracer provider with batch processor
    $tracerProvider = (new TracerProviderBuilder())
        ->addSpanProcessor($batchProcessor)
        ->build();
    
    // Get tracer instance
    $tracer = $tracerProvider->getTracer(
        'laravel-app',
        '1.0.0'
    );
    
    echo "✅ TracerProvider and Tracer created successfully\n\n";
    
    // Generate test traces
    echo "📊 Generating test traces...\n";
    
    for ($i = 1; $i <= 10; $i++) {
        $span = $tracer->spanBuilder("test.span.{$i}")
            ->setSpanKind(SpanKind::KIND_INTERNAL)
            ->setAttribute('test.iteration', $i)
            ->setAttribute('test.timestamp', microtime(true))
            ->setAttribute('test.implementation', 'official_sdk')
            ->startSpan();
        
        // Simulate some work
        usleep(10000); // 10ms
        
        $span->setStatus(StatusCode::STATUS_OK);
        $span->end();
        
        echo "   Created span {$i}/10\n";
    }
    
    echo "\n✅ All traces created successfully\n";
    
    // Force flush to see immediate results
    echo "🔄 Forcing flush of batch processor...\n";
    $flushResult = $batchProcessor->forceFlush();
    
    if ($flushResult) {
        echo "✅ Flush completed successfully\n";
    } else {
        echo "❌ Flush failed\n";
    }
    
    // Shutdown
    echo "🔄 Shutting down...\n";
    $batchProcessor->shutdown();
    $tracerProvider->shutdown();
    
    echo "✅ Official OpenTelemetry SDK test completed successfully!\n";
    echo "📈 Check your Last9 dashboard for the traces\n";
    
} catch (Exception $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
    echo "Stack trace:\n" . $e->getTraceAsString() . "\n";
} 