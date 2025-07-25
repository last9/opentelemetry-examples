<?php

// Direct test of OpenTelemetry export without Laravel
require_once __DIR__ . '/bootstrap/otel.php';

echo "🔍 DIRECT OPENTELEMETRY EXPORT TEST\n";
echo "====================================\n\n";

// Check if tracer is available
if (!isset($GLOBALS['otel_tracer'])) {
    echo "❌ OpenTelemetry tracer not available\n";
    exit(1);
}

echo "✅ OpenTelemetry tracer available\n";

// Create a test span
$tracer = $GLOBALS['otel_tracer'];
$span = $tracer->spanBuilder('test.direct.export')
    ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_INTERNAL)
    ->setAttribute('test.type', 'direct_export')
    ->setAttribute('test.timestamp', microtime(true))
    ->setAttribute('test.message', 'Testing direct export functionality')
    ->startSpan();

echo "✅ Test span created\n";

// Add some attributes and end the span
$span->setAttribute('test.status', 'completed');
$span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
$span->end();

echo "✅ Test span ended\n";

// Force flush
if (isset($GLOBALS['otel_batch_processor'])) {
    echo "🚀 Flushing spans...\n";
    $result = $GLOBALS['otel_batch_processor']->forceFlush();
    echo "✅ Flush result: " . ($result ? 'SUCCESS' : 'FAILED') . "\n";
} else {
    echo "❌ Batch processor not available\n";
}

// Show configuration
echo "\n📋 CONFIGURATION:\n";
echo "Service Name: " . ($_ENV['OTEL_SERVICE_NAME'] ?? 'laravel-app') . "\n";
echo "Endpoint: " . ($_ENV['OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'] ?? 'http://localhost:4318/v1/traces') . "\n";
echo "Protocol: " . ($_ENV['OTEL_EXPORTER_OTLP_PROTOCOL'] ?? 'http/protobuf') . "\n";
echo "Headers: " . (isset($_ENV['OTEL_EXPORTER_OTLP_HEADERS']) ? 'SET' : 'NOT SET') . "\n";

echo "\n🎯 Direct export test completed!\n";
echo "Check your OpenTelemetry backend for the 'test.direct.export' span.\n";