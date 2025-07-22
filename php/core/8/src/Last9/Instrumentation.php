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
    private ?TracerProvider $tracerProvider = null;
    private ?SpanInterface $rootSpan = null;
    private ?ScopeInterface $scope = null;
    private static ?self $instance = null;

    public static function init(string $appName, ?string $endpoint = null): self
    {
        if (self::$instance === null) {
            self::$instance = new self($appName, $endpoint);
        }
        return self::$instance;
    }

    private function __construct(string $appName, ?string $endpoint)
    {
        $this->initializeTracerProvider($endpoint);
        $this->initializeRootSpan($appName);
        $this->registerShutdownHandler();
    }

    private function initializeTracerProvider(?string $endpoint): void
    {
        $endpoint = $endpoint ?? getenv('OTEL_EXPORTER_OTLP_ENDPOINT');
        
        $transport = (new OtlpHttpTransportFactory())->create($endpoint, 'application/json');
        $exporter = new SpanExporter($transport);

        $spanProcessor = new BatchSpanProcessor(
            $exporter,
            ClockFactory::getDefault()
        );

        $this->tracerProvider = new TracerProvider($spanProcessor);

        MysqliInstrumentation::register(new CachedInstrumentation('io.opentelemetry.contrib.php.mysqli'));

        // Register the TracerProvider with Globals
        Globals::registerInitializer(function (Configurator $configurator) {
            return $configurator->withTracerProvider($this->tracerProvider);
        });
    }

    private function initializeRootSpan(string $appName): void
    {
        $tracer = $this->tracerProvider->getTracer('io.last9.php');
        
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
        if ($this->tracerProvider) {
            $this->tracerProvider->shutdown();
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