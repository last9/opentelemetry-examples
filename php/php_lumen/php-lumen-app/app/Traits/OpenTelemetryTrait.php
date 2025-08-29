<?php

namespace App\Traits;

use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\API\Trace\SpanInterface;
use Illuminate\Http\Response;

trait OpenTelemetryTrait
{
    protected ?SpanInterface $currentSpan = null;

    protected function traceOperation(string $operationName, callable $operation, array $attributes = [])
    {
        $tracer = app(TracerInterface::class);
        
        $span = $tracer->spanBuilder($operationName)
            ->setSpanKind(SpanKind::KIND_INTERNAL)
            ->setAttributes($attributes)
            ->startSpan();

        $scope = $span->activate();
        $this->currentSpan = $span;

        try {
            $result = $operation();
            
            // Check if result is an HTTP response with error status
            if ($result instanceof Response) {
                $this->handleHttpResponse($span, $result);
            } else {
                $span->setStatus(StatusCode::STATUS_OK);
            }
            
            return $result;
        } catch (\Exception $e) {
            $this->handleException($span, $e);
            throw $e;
        } finally {
            $span->end();
            $scope->detach();
            $this->currentSpan = null;
        }
    }

    /**
     * Handle HTTP response and set appropriate span status and attributes
     */
    protected function handleHttpResponse(SpanInterface $span, Response $response): void
    {
        $statusCode = $response->getStatusCode();
        
        // Set HTTP status code attribute
        $span->setAttributes([
            'http.status_code' => $statusCode,
            'http.response.size' => strlen($response->getContent()),
        ]);

        // Determine if this is an error response
        if ($statusCode >= 400) {
            $span->setStatus(StatusCode::STATUS_ERROR, "HTTP {$statusCode}");
            
            // Add error details
            $span->setAttributes([
                'error' => true,
                'error.type' => 'http_error',
                'error.message' => $this->getHttpErrorMessage($statusCode),
                'error.status_code' => $statusCode,
            ]);

            // Try to extract error message from response content
            $content = $response->getContent();
            if (!empty($content)) {
                $decoded = json_decode($content, true);
                if (isset($decoded['error'])) {
                    $span->setAttributes([
                        'error.details' => is_string($decoded['error']) ? $decoded['error'] : json_encode($decoded['error']),
                    ]);
                } elseif (isset($decoded['message'])) {
                    $span->setAttributes([
                        'error.details' => $decoded['message'],
                    ]);
                }
            }
        } else {
            $span->setStatus(StatusCode::STATUS_OK);
        }
    }

    /**
     * Handle exceptions and set appropriate span status and attributes
     */
    protected function handleException(SpanInterface $span, \Exception $e): void
    {
        $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
        $span->recordException($e);
        
        // Add comprehensive error attributes
        $span->setAttributes([
            'error' => true,
            'error.type' => get_class($e),
            'error.message' => $e->getMessage(),
            'error.code' => $e->getCode(),
            'error.file' => $e->getFile(),
            'error.line' => $e->getLine(),
        ]);

        // Add stack trace as an event
        $span->addEvent('exception.stack_trace', [
            'stack_trace' => $e->getTraceAsString(),
        ]);
    }

    /**
     * Get human-readable HTTP error message
     */
    protected function getHttpErrorMessage(int $statusCode): string
    {
        $messages = [
            400 => 'Bad Request',
            401 => 'Unauthorized',
            403 => 'Forbidden',
            404 => 'Not Found',
            405 => 'Method Not Allowed',
            408 => 'Request Timeout',
            409 => 'Conflict',
            412 => 'Precondition Failed',
            422 => 'Unprocessable Entity',
            429 => 'Too Many Requests',
            500 => 'Internal Server Error',
            501 => 'Not Implemented',
            502 => 'Bad Gateway',
            503 => 'Service Unavailable',
            504 => 'Gateway Timeout',
        ];

        return $messages[$statusCode] ?? "HTTP Error {$statusCode}";
    }

    protected function addSpanEvent(string $name, array $attributes = [])
    {
        if ($this->currentSpan) {
            $this->currentSpan->addEvent($name, $attributes);
        }
    }

    protected function setSpanAttribute(string $key, $value)
    {
        if ($this->currentSpan) {
            $this->currentSpan->setAttribute($key, $value);
        }
    }

    protected function traceDatabaseQuery(string $query, array $params, callable $operation)
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
            if ($this->currentSpan) {
                $spanContext = $this->currentSpan->getContext();
                return $spanContext->getTraceId();
            }
            return 'trace-id-not-available';
        } catch (\Exception $e) {
            return 'trace-id-not-available';
        }
    }

    protected function getCurrentSpanId(): string
    {
        try {
            if ($this->currentSpan) {
                $spanContext = $this->currentSpan->getContext();
                return $spanContext->getSpanId();
            }
            return 'span-id-not-available';
        } catch (\Exception $e) {
            return 'span-id-not-available';
        }
    }
}
