<?php

require_once __DIR__ . '/vendor/autoload.php';

use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\API\Trace\TracerInterface;

// Load environment variables
$dotenv = Dotenv\Dotenv::createImmutable(__DIR__);
$dotenv->load();

echo "🔧 Testing OpenTelemetry Configuration for Last9\n";
echo "================================================\n\n";

// Check environment variables
echo "📋 Environment Variables:\n";
echo "OTEL_SERVICE_NAME: " . ($_ENV['OTEL_SERVICE_NAME'] ?? 'NOT SET') . "\n";
echo "OTEL_TRACES_EXPORTER: " . ($_ENV['OTEL_TRACES_EXPORTER'] ?? 'NOT SET') . "\n";
echo "OTEL_EXPORTER_OTLP_HEADERS: " . ($_ENV['OTEL_EXPORTER_OTLP_HEADERS'] ?? 'NOT SET') . "\n";
echo "OTEL_RESOURCE_ATTRIBUTES: " . ($_ENV['OTEL_RESOURCE_ATTRIBUTES'] ?? 'NOT SET') . "\n\n";

try {
    // Create OTLP transport for Last9
    echo "🚀 Creating OTLP Transport...\n";
    $authHeader = $_ENV['OTEL_EXPORTER_OTLP_HEADERS'] ?? 'Authorization=Basic bGFzdDk6bGFzdDk=';
    // Extract the actual authorization value
    $authValue = str_replace('Authorization=', '', $authHeader);
    
    $headers = [
        'Authorization' => $authValue,
        'Content-Type' => 'application/json'
    ];
    
    $transport = (new OtlpHttpTransportFactory())->create(
        'https://otlp-aps1.last9.io:443/v1/traces',
        'application/json',
        $headers
    );
    echo "✅ OTLP Transport created successfully\n\n";
    
    // Create exporter
    echo "📤 Creating Span Exporter...\n";
    $exporter = new SpanExporter($transport);
    echo "✅ Span Exporter created successfully\n\n";
    
    // Create tracer provider
    echo "🔧 Creating Tracer Provider...\n";
    $tracerProvider = new TracerProvider(
        new SimpleSpanProcessor($exporter)
    );
    echo "✅ Tracer Provider created successfully\n\n";
    
    // Get tracer
    echo "🎯 Getting Tracer...\n";
    $tracer = $tracerProvider->getTracer($_ENV['OTEL_SERVICE_NAME'] ?? 'lumen-test-app');
    echo "✅ Tracer obtained successfully\n\n";
    
    // Create a test span
    echo "📊 Creating Test Span...\n";
    $span = $tracer->spanBuilder('test.span')
        ->setAttributes([
            'test.attribute' => 'test_value',
            'test.timestamp' => date('c')
        ])
        ->startSpan();
    
    $span->addEvent('test.event', [
        'message' => 'Test event from Lumen app',
        'timestamp' => date('c')
    ]);
    
    // Simulate some work
    usleep(100000); // 100ms
    
    $span->end();
    echo "✅ Test span created and ended successfully\n\n";
    
    // Force flush to send data
    echo "📤 Flushing spans to Last9...\n";
    $tracerProvider->forceFlush();
    echo "✅ Spans flushed successfully\n\n";
    
    echo "🎉 OpenTelemetry configuration test completed successfully!\n";
    echo "📊 Check your Last9 dashboard to see the test span.\n";
    
} catch (Exception $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
    echo "📋 Stack trace:\n" . $e->getTraceAsString() . "\n";
}
