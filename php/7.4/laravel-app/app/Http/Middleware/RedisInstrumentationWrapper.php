<?php

namespace App\Http\Middleware;

use Exception;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\SemConv\TraceAttributes;

class RedisInstrumentationWrapper
{
    protected $redis;
    protected $tracer;

    public function __construct($redis)
    {
        $this->redis = $redis;
        $this->tracer = $GLOBALS['otel_tracer'] ?? null;
    }

    public function __call($method, $args)
    {
        if (!$this->tracer) {
            return call_user_func_array([$this->redis, $method], $args);
        }

        $span = $this->tracer->spanBuilder('redis.' . strtolower($method))
            ->setSpanKind(SpanKind::KIND_CLIENT)
            ->setAttribute(TraceAttributes::DB_SYSTEM, 'redis')
            ->setAttribute('db.operation', strtoupper($method))
            ->setAttribute('redis.command', strtoupper($method))
            ->startSpan();

        // Add key information for better observability
        if (!empty($args) && is_string($args[0])) {
            $span->setAttribute('redis.key', $args[0]);
        }

        // Add Redis connection info
        $config = config('database.redis.default', []);
        if (!empty($config['host'])) {
            $span->setAttribute('server.address', $config['host']);
        }
        if (!empty($config['port'])) {
            $span->setAttribute('server.port', $config['port']);
        }

        try {
            $result = call_user_func_array([$this->redis, $method], $args);
            
            $span->setStatus(StatusCode::STATUS_OK);
            $span->end();
            
            return $result;
            
        } catch (Exception $e) {
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            $span->end();
            throw $e;
        }
    }
}