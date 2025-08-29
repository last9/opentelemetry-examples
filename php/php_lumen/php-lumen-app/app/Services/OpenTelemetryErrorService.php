<?php

namespace App\Services;

use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\API\Trace\SpanInterface;
use Illuminate\Http\Response;
use Throwable;

/**
 * Generic OpenTelemetry Error Handling Service
 * 
 * This service provides comprehensive error tracing capabilities that can be used
 * across different applications and frameworks. It captures error messages,
 * exceptions, HTTP status codes, and provides detailed error context.
 */
class OpenTelemetryErrorService
{
    protected TracerInterface $tracer;

    public function __construct(TracerInterface $tracer)
    {
        $this->tracer = $tracer;
    }

    /**
     * Trace an operation with comprehensive error handling
     */
    public function traceOperation(string $operationName, callable $operation, array $attributes = []): mixed
    {
        $span = $this->tracer->spanBuilder($operationName)
            ->setSpanKind(SpanKind::KIND_INTERNAL)
            ->setAttributes($attributes)
            ->startSpan();

        $scope = $span->activate();

        try {
            $result = $operation();
            
            // Check if result is an HTTP response with error status
            if ($result instanceof Response) {
                $this->handleHttpResponse($span, $result);
            } else {
                $span->setStatus(StatusCode::STATUS_OK);
            }
            
            return $result;
        } catch (Throwable $e) {
            $this->handleException($span, $e);
            throw $e;
        } finally {
            $span->end();
            $scope->detach();
        }
    }

    /**
     * Handle HTTP response and set appropriate span status and attributes
     */
    public function handleHttpResponse(SpanInterface $span, Response $response): void
    {
        $statusCode = $response->getStatusCode();
        
        // Set HTTP status code attribute
        $span->setAttributes([
            'http.status_code' => $statusCode,
            'http.response.size' => strlen($response->getContent()),
            'http.response.content_type' => $response->headers->get('Content-Type', 'unknown'),
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
            $this->extractErrorDetailsFromResponse($span, $response);

            // Add error event
            $span->addEvent('http.error', [
                'status_code' => $statusCode,
                'error_message' => $this->getHttpErrorMessage($statusCode),
            ]);
        } else {
            $span->setStatus(StatusCode::STATUS_OK);
        }
    }

    /**
     * Handle exceptions and set appropriate span status and attributes
     */
    public function handleException(SpanInterface $span, Throwable $e): void
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

        // Add specific attributes based on exception type
        $this->addExceptionSpecificAttributes($span, $e);

        // Add stack trace as an event
        $span->addEvent('exception.stack_trace', [
            'stack_trace' => $e->getTraceAsString(),
        ]);
    }

    /**
     * Extract error details from HTTP response content
     */
    protected function extractErrorDetailsFromResponse(SpanInterface $span, Response $response): void
    {
        $content = $response->getContent();
        if (empty($content)) {
            return;
        }

        $decoded = json_decode($content, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            // If not JSON, try to extract error message from plain text
            if (strlen($content) < 1000) { // Only for reasonable content size
                $span->setAttributes([
                    'error.details' => $content,
                ]);
            }
            return;
        }

        // Extract error information from JSON response
        $errorDetails = [];
        
        if (isset($decoded['error'])) {
            $errorDetails['error'] = is_string($decoded['error']) ? $decoded['error'] : json_encode($decoded['error']);
        }
        
        if (isset($decoded['message'])) {
            $errorDetails['message'] = $decoded['message'];
        }
        
        if (isset($decoded['details'])) {
            $errorDetails['details'] = is_string($decoded['details']) ? $decoded['details'] : json_encode($decoded['details']);
        }
        
        if (isset($decoded['validation_errors'])) {
            $errorDetails['validation_errors'] = json_encode($decoded['validation_errors']);
        }

        if (!empty($errorDetails)) {
            $span->setAttributes($errorDetails);
        }
    }

    /**
     * Add exception-specific attributes based on exception type
     */
    protected function addExceptionSpecificAttributes(SpanInterface $span, Throwable $e): void
    {
        // HTTP Exceptions
        if ($e instanceof \Symfony\Component\HttpKernel\Exception\HttpException) {
            $span->setAttributes([
                'http.status_code' => $e->getStatusCode(),
                'error.status_code' => $e->getStatusCode(),
            ]);
        }

        // Validation Exceptions
        if ($e instanceof \Illuminate\Validation\ValidationException) {
            $span->setAttributes([
                'validation.errors' => json_encode($e->errors()),
                'error.type' => 'validation_error',
            ]);
        }

        // Database Exceptions
        if ($e instanceof \Illuminate\Database\QueryException) {
            $span->setAttributes([
                'db.error' => true,
                'db.error_code' => $e->getCode(),
                'db.error_message' => $e->getMessage(),
                'error.type' => 'database_error',
            ]);
        }

        // Authentication Exceptions
        if ($e instanceof \Illuminate\Auth\AuthenticationException) {
            $span->setAttributes([
                'auth.error' => true,
                'error.type' => 'authentication_error',
            ]);
        }

        // Authorization Exceptions
        if ($e instanceof \Illuminate\Auth\Access\AuthorizationException) {
            $span->setAttributes([
                'auth.error' => true,
                'error.type' => 'authorization_error',
            ]);
        }

        // Model Not Found Exceptions
        if ($e instanceof \Illuminate\Database\Eloquent\ModelNotFoundException) {
            $span->setAttributes([
                'model.not_found' => true,
                'error.type' => 'model_not_found',
            ]);
        }
    }

    /**
     * Get human-readable HTTP error message
     */
    public function getHttpErrorMessage(int $statusCode): string
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

    /**
     * Create a span for database operations
     */
    public function traceDatabaseQuery(string $query, array $params, callable $operation): mixed
    {
        return $this->traceOperation('database.query', $operation, [
            'db.statement' => $query,
            'db.parameters' => json_encode($params),
            'db.system' => 'mysql', // or your database type
            'span.kind' => 'client',
        ]);
    }

    /**
     * Create a span for external API calls
     */
    public function traceExternalApiCall(string $url, string $method, callable $operation): mixed
    {
        return $this->traceOperation('external.api.call', $operation, [
            'http.url' => $url,
            'http.method' => $method,
            'span.kind' => 'client',
        ]);
    }

    /**
     * Create a span for cache operations
     */
    public function traceCacheOperation(string $operation, string $key, callable $cacheCall): mixed
    {
        return $this->traceOperation('cache.operation', $cacheCall, [
            'cache.operation' => $operation,
            'cache.key' => $key,
        ]);
    }

    /**
     * Create a span for queue jobs
     */
    public function traceQueueJob(string $jobName, callable $jobOperation): mixed
    {
        return $this->traceOperation('queue.job', $jobOperation, [
            'queue.job.name' => $jobName,
            'span.kind' => 'consumer',
        ]);
    }

    /**
     * Create a span for file operations
     */
    public function traceFileOperation(string $operation, string $filePath, callable $fileOperation): mixed
    {
        return $this->traceOperation('file.operation', $fileOperation, [
            'file.operation' => $operation,
            'file.path' => $filePath,
        ]);
    }

    /**
     * Create a span for email operations
     */
    public function traceEmailOperation(string $operation, string $recipient, callable $emailOperation): mixed
    {
        return $this->traceOperation('email.operation', $emailOperation, [
            'email.operation' => $operation,
            'email.recipient' => $recipient,
        ]);
    }

    /**
     * Add custom error attributes to current span
     */
    public function addErrorAttributes(array $attributes): void
    {
        try {
            $span = $this->tracer->spanBuilder('custom.error')
                ->startSpan();
            
            $span->setAttributes(array_merge([
                'error' => true,
                'error.timestamp' => now()->toISOString(),
            ], $attributes));
            
            $span->setStatus(StatusCode::STATUS_ERROR);
            $span->end();
        } catch (\Exception $e) {
            // Silently fail if OpenTelemetry is not available
        }
    }

    /**
     * Record a custom error event
     */
    public function recordErrorEvent(string $eventName, array $attributes = []): void
    {
        try {
            $span = $this->tracer->spanBuilder('error.event')
                ->startSpan();
            
            $span->addEvent($eventName, array_merge([
                'error' => true,
                'error.timestamp' => now()->toISOString(),
            ], $attributes));
            
            $span->setStatus(StatusCode::STATUS_ERROR);
            $span->end();
        } catch (\Exception $e) {
            // Silently fail if OpenTelemetry is not available
        }
    }
}
