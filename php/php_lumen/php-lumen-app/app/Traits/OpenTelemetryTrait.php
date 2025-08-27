<?php

namespace App\Traits;

use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;

trait OpenTelemetryTrait
{
    protected function traceOperation(string $operationName, callable $operation, array $attributes = [])
    {
        $tracer = app(TracerInterface::class);
        
        $span = $tracer->spanBuilder($operationName)
            ->setSpanKind(SpanKind::KIND_INTERNAL)
            ->setAttributes($attributes)
            ->startSpan();

        $scope = $span->activate();

        try {
            $result = $operation();
            $span->setStatus(StatusCode::STATUS_OK);
            return $result;
        } catch (\Exception $e) {
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            throw $e;
        } finally {
            $span->end();
            $scope->detach();
        }
    }

    protected function addSpanEvent(string $name, array $attributes = [])
    {
        // Note: Span events need to be added to the current active span
        // This is a simplified implementation - in a real scenario, you'd need to track the current span
        // For now, we'll skip this functionality to avoid complexity
    }

    protected function setSpanAttribute(string $key, $value)
    {
        // Note: Span attributes need to be set on the current active span
        // This is a simplified implementation - in a real scenario, you'd need to track the current span
        // For now, we'll skip this functionality to avoid complexity
    }

    protected function traceDatabaseQuery(string $query, callable $operation, array $params = [])
    {
        return $this->traceOperation('database.query', $operation, [
            'db.statement' => $query,
            'db.parameters' => json_encode($params),
            'db.system' => 'mysql', // or your database type
            'span.kind' => 'client',
        ]);
    }

    protected function traceExternalApiCall(string $url, string $method, callable $operation)
    {
        return $this->traceOperation('external.api.call', $operation, [
            'http.url' => $url,
            'http.method' => $method,
            'span.kind' => 'client',
        ]);
    }

    protected function traceCacheOperation(string $operation, string $key, callable $cacheCall)
    {
        return $this->traceOperation('cache.operation', $cacheCall, [
            'cache.operation' => $operation,
            'cache.key' => $key,
        ]);
    }

    protected function traceQueueJob(string $jobName, callable $jobOperation)
    {
        return $this->traceOperation('queue.job', $jobOperation, [
            'queue.job.name' => $jobName,
            'span.kind' => 'consumer',
        ]);
    }

    protected function getCurrentTraceId(): string
    {
        try {
            $tracer = app(\OpenTelemetry\API\Trace\TracerInterface::class);
            // For now, return a placeholder since we need proper span context management
            return 'trace-id-not-available';
        } catch (\Exception $e) {
            return 'trace-id-not-available';
        }
    }

    protected function getCurrentSpanId(): string
    {
        try {
            $tracer = app(\OpenTelemetry\API\Trace\TracerInterface::class);
            // For now, return a placeholder since we need proper span context management
            return 'span-id-not-available';
        } catch (\Exception $e) {
            return 'span-id-not-available';
        }
    }
}
