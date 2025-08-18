<?php

namespace App\Jobs;

use Exception;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\Context\Context;

abstract class BaseTracedJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    protected $traceContext = [];

    abstract public function handleJob();

    public function setTraceContext($traceContext)
    {
        $this->traceContext = $traceContext;
    }

    public function handle()
    {
        $tracer = $GLOBALS['otel_tracer'] ?? null;
        if (!$tracer) {
            return $this->handleJob();
        }

        // Extract parent context from trace context if available
        $parentContext = Context::getCurrent();
        if (!empty($this->traceContext)) {
            try {
                $parentContext = \OpenTelemetry\API\Trace\Propagation\TraceContextPropagator::getInstance()->extract($this->traceContext);
            } catch (Exception $e) {
                // Fall back to current context if extraction fails
            }
        }

        $spanBuilder = $tracer->spanBuilder('queue.job.process')
            ->setSpanKind(SpanKind::KIND_CONSUMER)
            ->setAttribute('messaging.system', config('queue.default') === 'redis' ? 'redis' : config('queue.default'))
            ->setAttribute('messaging.operation', 'process')
            ->setAttribute('queue.job.class', get_class($this))
            ->setAttribute('queue.name', $this->queue ?? 'default');

        // Set parent context to link spans
        if ($parentContext !== Context::getCurrent()) {
            $spanBuilder->setParent($parentContext);
        }

        $span = $spanBuilder->startSpan();
        $scope = $span->activate();

        try {
            $result = $this->handleJob();
            
            $span->setStatus(StatusCode::STATUS_OK);
            $span->end();
            $scope->detach();
            
            return $result;
            
        } catch (Exception $e) {
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            $span->end();
            $scope->detach();
            throw $e;
        }
    }
}