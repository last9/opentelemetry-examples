<?php

namespace App\Exceptions;

use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Validation\ValidationException;
use Laravel\Lumen\Exceptions\Handler as ExceptionHandler;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Throwable;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\API\Trace\StatusCode;
use Illuminate\Http\JsonResponse;

class Handler extends ExceptionHandler
{
    /**
     * A list of the exception types that should not be reported.
     *
     * @var array
     */
    protected $dontReport = [
        AuthorizationException::class,
        HttpException::class,
        ModelNotFoundException::class,
        ValidationException::class,
    ];

    /**
     * Report or log an exception.
     *
     * This is a great spot to send exceptions to Sentry, Bugsnag, etc.
     *
     * @param  \Throwable  $exception
     * @return void
     *
     * @throws \Exception
     */
    public function report(Throwable $exception)
    {
        $this->traceException($exception);
        parent::report($exception);
    }

    /**
     * Render an exception into an HTTP response.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Throwable  $exception
     * @return \Illuminate\Http\Response|\Illuminate\Http\JsonResponse
     *
     * @throws \Throwable
     */
    public function render($request, Throwable $exception)
    {
        $this->traceException($exception);
        
        // For API requests, return JSON responses
        if ($request->expectsJson() || $request->is('api/*')) {
            return $this->renderJsonException($exception);
        }
        
        return parent::render($request, $exception);
    }

    /**
     * Trace exception in OpenTelemetry
     */
    protected function traceException(Throwable $exception): void
    {
        try {
            $tracer = app(TracerInterface::class);
            $span = $tracer->spanBuilder('exception.handler')
                ->startSpan();
            
            $scope = $span->activate();
            
            // Set error status
            $span->setStatus(StatusCode::STATUS_ERROR, $exception->getMessage());
            $span->recordException($exception);
            
            // Add comprehensive error attributes
            $span->setAttributes([
                'error' => true,
                'error.type' => get_class($exception),
                'error.message' => $exception->getMessage(),
                'error.code' => $exception->getCode(),
                'error.file' => $exception->getFile(),
                'error.line' => $exception->getLine(),
                'exception.handled' => true,
            ]);

            // Add stack trace as an event
            $span->addEvent('exception.stack_trace', [
                'stack_trace' => $exception->getTraceAsString(),
            ]);

            // Add specific attributes based on exception type
            if ($exception instanceof HttpException) {
                $span->setAttributes([
                    'http.status_code' => $exception->getStatusCode(),
                    'error.status_code' => $exception->getStatusCode(),
                ]);
            }

            if ($exception instanceof ValidationException) {
                $span->setAttributes([
                    'validation.errors' => json_encode($exception->errors()),
                    'error.type' => 'validation_error',
                ]);
            }

            $span->end();
            $scope->detach();
        } catch (\Exception $e) {
            // Silently fail if OpenTelemetry is not available
            // This prevents the error handler from causing additional errors
        }
    }

    /**
     * Render exception as JSON response
     */
    protected function renderJsonException(Throwable $exception): JsonResponse
    {
        $statusCode = 500;
        $message = 'Internal Server Error';
        $details = null;

        if ($exception instanceof HttpException) {
            $statusCode = $exception->getStatusCode();
            $message = $exception->getMessage() ?: $this->getHttpErrorMessage($statusCode);
        } elseif ($exception instanceof ValidationException) {
            $statusCode = 422;
            $message = 'Validation failed';
            $details = $exception->errors();
        } elseif ($exception instanceof ModelNotFoundException) {
            $statusCode = 404;
            $message = 'Resource not found';
        } elseif ($exception instanceof AuthorizationException) {
            $statusCode = 403;
            $message = 'Access forbidden';
        } else {
            $message = $exception->getMessage() ?: 'Internal Server Error';
        }

        $response = [
            'error' => true,
            'message' => $message,
            'status_code' => $statusCode,
        ];

        if ($details !== null) {
            $response['details'] = $details;
        }

        // Add debug information in development
        if (config('app.debug', false)) {
            $response['debug'] = [
                'exception' => get_class($exception),
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => $exception->getTraceAsString(),
            ];
        }

        return response()->json($response, $statusCode);
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
