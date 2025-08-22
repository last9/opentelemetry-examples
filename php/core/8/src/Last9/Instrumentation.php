<?php

namespace Last9;

use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\API\Trace\SpanInterface;
use OpenTelemetry\Context\ScopeInterface;
use OpenTelemetry\API\Globals;
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
        
        // Register MySQL instrumentation (if available)
        try {
            if (class_exists('OpenTelemetry\Contrib\Instrumentation\MySqli\MysqliInstrumentation')) {
                MysqliInstrumentation::register(new CachedInstrumentation('io.opentelemetry.contrib.php.mysqli'));
            }
        } catch (\Exception $e) {
            error_log("Error registering MySQL instrumentation: " . $e->getMessage());
        }
        
        $this->initializeRootSpan($appName);
        $this->registerShutdownHandler();
    }


    private function initializeRootSpan(string $appName): void
    {
        // Use global TracerProvider (auto-configured via environment variables)
        $tracerProvider = Globals::tracerProvider();
        $tracer = $tracerProvider->getTracer('io.last9.php');
        
        // Get HTTP method and endpoint from server globals
        $method = $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN';
        $endpoint = $_SERVER['REQUEST_URI'] ?? '/';
        $spanName = "{$method} {$endpoint}";
        
        $this->rootSpan = $tracer->spanBuilder($spanName)
            ->setSpanKind(SpanKind::KIND_SERVER)
            ->startSpan();
            
        $this->scope = $this->rootSpan->activate();
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
        if ($this->scope) {
            $this->scope->detach();
        }
        if ($this->rootSpan) {
            $this->rootSpan->end();
        }
        
        // Force flush spans to ensure they get exported before process ends
        try {
            $tracerProvider = Globals::tracerProvider();
            if ($tracerProvider && method_exists($tracerProvider, 'forceFlush')) {
                $tracerProvider->forceFlush();
            }
        } catch (\Exception $e) {
            error_log("Error flushing TracerProvider: " . $e->getMessage());
        }
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