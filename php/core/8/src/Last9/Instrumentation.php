<?php

namespace Last9;

use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\Context\Context;
use OpenTelemetry\API\Trace\SpanInterface;
use OpenTelemetry\Context\ScopeInterface;
use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Instrumentation\Configurator;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Common\Time\ClockFactory;
use OpenTelemetry\API\Instrumentation\CachedInstrumentation;
use OpenTelemetry\Contrib\Instrumentation\MySqli\MysqliInstrumentation;

class Instrumentation
{
    private ?SpanInterface $rootSpan = null;
    private ?ScopeInterface $scope = null;
    private static ?self $instance = null;

    public static function init(string $appName): self
    {
        if (self::$instance === null) {
            self::$instance = new self($appName);
        }
        return self::$instance;
    }

    private function __construct(string $appName)
    {
        // Debug environment variables
        $endpoint = getenv('OTEL_EXPORTER_OTLP_ENDPOINT');
        $headers = getenv('OTEL_EXPORTER_OTLP_HEADERS');
        $serviceName = getenv('OTEL_SERVICE_NAME');
        
        error_log("=== OTEL DEBUG INFO ===");
        error_log("Endpoint: " . ($endpoint ?: 'NOT SET'));
        error_log("Headers: " . ($headers ?: 'NOT SET'));
        error_log("Service Name: " . ($serviceName ?: 'NOT SET'));
        error_log("PHP Version: " . PHP_VERSION);
        error_log("Using AUTO-INSTRUMENTATION approach");
        error_log("========================");
        
        // Register MySQL instrumentation
        try {
            MysqliInstrumentation::register(new CachedInstrumentation('io.opentelemetry.contrib.php.mysqli'));
            error_log("MySQL instrumentation registered successfully");
        } catch (\Exception $e) {
            error_log("Error registering MySQL instrumentation: " . $e->getMessage());
        }
        
        $this->initializeRootSpan($appName);
        $this->registerShutdownHandler();
    }


    private function initializeRootSpan(string $appName): void
    {
        // Use global TracerProvider (configured via environment variables)
        $tracer = Globals::tracerProvider()->getTracer('io.last9.php');
        
        // Get HTTP method and endpoint from server globals
        $method = $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN';
        $endpoint = $_SERVER['REQUEST_URI'] ?? '/';
        $spanName = "{$method} {$endpoint}";
        
        $this->rootSpan = $tracer->spanBuilder($spanName)
            ->setSpanKind(SpanKind::KIND_SERVER)
            ->startSpan();
            
        $this->scope = $this->rootSpan->activate();
        
        error_log("Created root span: " . $spanName . " with ID: " . $this->rootSpan->getContext()->getSpanId());
    }

    public function setError(\Throwable $error): void
    {
        $this->rootSpan->setStatus(StatusCode::STATUS_ERROR, $error->getMessage());
    }

    public function setSuccess(): void
    {
        if (!$this->rootSpan) {
            throw new \RuntimeException('Root span not initialized');
        }
        $this->rootSpan->setStatus(StatusCode::STATUS_OK);
    }

    private function end(): void
    {
        error_log("Ending instrumentation...");
        if ($this->scope) {
            $this->scope->detach();
            error_log("Scope detached");
        }
        if ($this->rootSpan) {
            $this->rootSpan->end();
            error_log("Root span ended: " . $this->rootSpan->getContext()->getSpanId());
        }
        
        // Force flush spans to ensure they get exported before process ends
        try {
            error_log("Flushing TracerProvider...");
            $tracerProvider = Globals::tracerProvider();
            if ($tracerProvider && method_exists($tracerProvider, 'forceFlush')) {
                $tracerProvider->forceFlush();
                error_log("TracerProvider flushed successfully");
            } else {
                error_log("TracerProvider doesn't support forceFlush");
            }
        } catch (\Exception $e) {
            error_log("Error flushing TracerProvider: " . $e->getMessage());
        }
        
        error_log("Instrumentation ended");
    }

    private function registerShutdownHandler(): void
    {
        register_shutdown_function(function() {
            $this->end();
        });
    }

    // Prevent cloning of the instance
    private function __clone() {}

    // Prevent unserializing of the instance
    public function __wakeup()
    {
        throw new \Exception("Cannot unserialize singleton");
    }
} 