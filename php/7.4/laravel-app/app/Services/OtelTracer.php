<?php

namespace App\Services;

use OpenTelemetry\Contrib\Otlp\SpanExporterFactory;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Trace\TracerProviderBuilder;
use OpenTelemetry\SDK\Common\Time\ClockFactory;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\SDK\Common\Configuration\Configuration;
use OpenTelemetry\SDK\Common\Configuration\Variables;
use OpenTelemetry\SDK\Common\Configuration\Defaults;
use OpenTelemetry\SDK\Common\Otlp\HttpEndpointResolver;
use OpenTelemetry\Contrib\Otlp\OtlpUtil;
use OpenTelemetry\Contrib\Otlp\Protocols;
use OpenTelemetry\SDK\FactoryRegistry;
use OpenTelemetry\SDK\Common\Export\TransportFactoryInterface;
use OpenTelemetry\SDK\Common\Export\TransportInterface;
use OpenTelemetry\SDK\Common\Future\CancellationInterface;
use OpenTelemetry\SDK\Trace\SpanExporterInterface;
use OpenTelemetry\SDK\Trace\ReadableSpanInterface;
use OpenTelemetry\SDK\Trace\ReadWriteSpanInterface;
use OpenTelemetry\SDK\Trace\SpanDataInterface;
use OpenTelemetry\SDK\Trace\SpanProcessorInterface;
use OpenTelemetry\Context\Context;
use OpenTelemetry\Context\ContextInterface;
use OpenTelemetry\API\Metrics\MeterProviderInterface;
use OpenTelemetry\API\Metrics\ObserverInterface;
use OpenTelemetry\SDK\Behavior\LogsMessagesTrait;
use OpenTelemetry\SDK\Common\Future\FutureInterface;
use OpenTelemetry\SDK\Common\Time\ClockInterface;
use SplQueue;
use Throwable;
use InvalidArgumentException;
use function assert;
use function count;
use function sprintf;

class OtelTracer
{
    private static $instance = null;
    private TracerProvider $tracerProvider;
    private TracerInterface $tracer;
    private BatchSpanProcessor $batchProcessor;
    private SpanExporterInterface $exporter;
    private ClockInterface $clock;
    
    // Configuration constants from official SDK
    public const DEFAULT_SCHEDULE_DELAY = 5000;
    public const DEFAULT_EXPORT_TIMEOUT = 30000;
    public const DEFAULT_MAX_QUEUE_SIZE = 2048;
    public const DEFAULT_MAX_EXPORT_BATCH_SIZE = 512;
    
    private function __construct()
    {
        $this->initializeTracer();
    }
    
    public static function getInstance(): self
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    private function initializeTracer(): void
    {
        // Set up environment variables for the official SDK
        $this->setupEnvironment();
        
        // Create the OTLP exporter using the official factory
        $exporterFactory = new SpanExporterFactory();
        $this->exporter = $exporterFactory->create();
        
        // Create clock for batch processor
        $this->clock = ClockFactory::getDefault();
        
        // Create batch processor with official SDK defaults
        $this->batchProcessor = new BatchSpanProcessor(
            $this->exporter,
            $this->clock,
            self::DEFAULT_MAX_QUEUE_SIZE,
            self::DEFAULT_SCHEDULE_DELAY,
            self::DEFAULT_EXPORT_TIMEOUT,
            self::DEFAULT_MAX_EXPORT_BATCH_SIZE,
            true // autoFlush
        );
        
        // Create tracer provider with batch processor
        $this->tracerProvider = (new TracerProviderBuilder())
            ->addSpanProcessor($this->batchProcessor)
            ->build();
        
        // Get tracer instance
        $this->tracer = $this->tracerProvider->getTracer(
            env('OTEL_SERVICE_NAME', 'laravel-app'),
            env('OTEL_SERVICE_VERSION', '1.0.0')
        );
        
        // Register shutdown function to flush remaining traces
        register_shutdown_function([$this, 'shutdown']);
    }
    
    private function setupEnvironment(): void
    {
        // Environment variables are now handled by the bootstrap file
        // No need to set them here as they should be configured in .env
    }
    
    /**
     * Create a new span
     */
    public function createSpan(string $name, array $attributes = [], int $kind = SpanKind::KIND_INTERNAL): SpanInterface
    {
        $spanBuilder = $this->tracer->spanBuilder($name);
        
        // Add attributes
        foreach ($attributes as $key => $value) {
            $spanBuilder->setAttribute($key, $value);
        }
        
        // Set span kind
        $spanBuilder->setSpanKind($kind);
        
        return $spanBuilder->startSpan();
    }
    
    /**
     * Create a trace (span that starts and ends immediately)
     */
    public function createTrace(string $name, array $attributes = []): void
    {
        $span = $this->createSpan($name, $attributes);
        $span->end();
    }
    
    /**
     * Trace a database operation
     */
    public function traceDatabase(string $query, ?string $dbName = null, ?string $connectionName = null, ?float $duration = null, ?int $rowCount = null, ?Throwable $error = null, ?string $customSpanName = null): void
    {
        $operation = $this->extractDbOperation($query);
        $tableName = $this->extractTableName($query, $operation);
        
        $spanName = $customSpanName ?: 'db.' . $operation . ($tableName ? " {$tableName}" : '');
        
        $span = $this->tracer->spanBuilder($spanName)
            ->setSpanKind(SpanKind::KIND_CLIENT)
            ->setAttribute('db.system', 'mysql')
            ->setAttribute('db.statement', $query)
            ->setAttribute('db.operation', $operation)
            ->setAttribute('db.name', $dbName ?? env('DB_DATABASE', 'laravel'))
            ->setAttribute('server.address', env('DB_HOST', 'mysql'))
            ->setAttribute('server.port', (int)env('DB_PORT', 3306))
            ->setAttribute('network.transport', 'tcp')
            ->setAttribute('network.type', 'ipv4')
            ->startSpan();
        
        if ($tableName) {
            $span->setAttribute('db.sql.table', $tableName);
        }
        
        if ($duration !== null) {
            $span->setAttribute('db.duration', (string)$duration);
        }
        
        if ($rowCount !== null) {
            $span->setAttribute('db.rows_affected', $rowCount);
        }
        
        if ($error) {
            $span->setStatus(StatusCode::STATUS_ERROR, $error->getMessage());
            $span->recordException($error);
        } else {
            $span->setStatus(StatusCode::STATUS_OK);
        }
        
        $span->end();
    }
    
    /**
     * Force flush all pending traces
     */
    public function forceFlush(): bool
    {
        return $this->batchProcessor->forceFlush();
    }
    
    /**
     * Get current batch processor statistics
     */
    public function getBatchStats(): array
    {
        // Note: The official SDK doesn't expose these stats directly
        // We'll return basic info
        return [
            'processor_type' => 'BatchSpanProcessor',
            'max_queue_size' => self::DEFAULT_MAX_QUEUE_SIZE,
            'max_export_batch_size' => self::DEFAULT_MAX_EXPORT_BATCH_SIZE,
            'scheduled_delay_ms' => self::DEFAULT_SCHEDULE_DELAY,
            'export_timeout_ms' => self::DEFAULT_EXPORT_TIMEOUT,
        ];
    }
    
    /**
     * Shutdown the tracer
     */
    public function shutdown(): void
    {
        $this->batchProcessor->shutdown();
        $this->tracerProvider->shutdown();
    }
    
    private function extractDbOperation(string $query): string
    {
        $query = trim(strtoupper($query));
        if (preg_match('/^(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE|REPLACE|SHOW|DESCRIBE|EXPLAIN)/', $query, $matches)) {
            return strtolower($matches[1]);
        }
        return 'query';
    }
    
    private function extractTableName(string $query, string $operation): ?string
    {
        $query = trim($query);
        $tableName = null;
        
        switch (strtolower($operation)) {
            case 'select':
                if (preg_match('/\bFROM\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'insert':
                if (preg_match('/\bINTO\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'update':
                if (preg_match('/\bUPDATE\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
            case 'delete':
                if (preg_match('/\bFROM\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query, $matches)) {
                    $tableName = $matches[1];
                }
                break;
        }
        
        return $tableName;
    }
} 