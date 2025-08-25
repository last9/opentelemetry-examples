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
            ])
            ->startSpan();

        $scope = $span->activate();

        try {
            $response = $next($request);

            $span->setAttributes([
                TraceAttributes::HTTP_STATUS_CODE => $response->getStatusCode(),
                'http.response.size' => strlen($response->getContent()),
            ]);

            $span->setStatus(StatusCode::STATUS_OK);

            return $response;
        } catch (\Exception $e) {
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            throw $e;
        } finally {
            $span->end();
            $scope->detach();
        }
    }
}
