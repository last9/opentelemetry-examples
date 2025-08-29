<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\SemConv\TraceAttributes;
use Carbon\Carbon;

class OpenTelemetryMiddleware
{
    protected TracerInterface $tracer;

    public function __construct(TracerInterface $tracer)
    {
        $this->tracer = $tracer;
    }

    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next)
    {
        $span = $this->tracer->spanBuilder('http.request')
            ->setSpanKind(SpanKind::KIND_SERVER)
            ->setAttributes([
                TraceAttributes::HTTP_METHOD => $request->method(),
                TraceAttributes::HTTP_URL => $request->fullUrl(),
                'http.request.id' => uniqid(),
                'http.request.timestamp' => Carbon::now()->toISOString(),
                'http.user_agent' => $request->userAgent(),
                'http.request.size' => strlen($request->getContent()),
            ])
            ->startSpan();

        $scope = $span->activate();

        try {
            $response = $next($request);

            $this->handleHttpResponse($span, $response);

            return $response;
        } catch (\Exception $e) {
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
    protected function handleHttpResponse($span, $response): void
    {
        $statusCode = $response->getStatusCode();
        
        // Set HTTP status code attribute
        $span->setAttributes([
            TraceAttributes::HTTP_STATUS_CODE => $statusCode,
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
    protected function handleException($span, \Exception $e): void
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
}
