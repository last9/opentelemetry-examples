<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     *
     * @return void
     */
    public function register()
    {
        //
    }

    /**
     * Bootstrap any application services.
     *
     * @return void
     */
    public function boot()
    {
        $tracer = $GLOBALS['otel_tracer'] ?? null;
        
        \Illuminate\Support\Facades\DB::listen(function ($query) use ($tracer) {
            if (!$tracer) {
                return;
            }
            
            try {
                $connectionName = $query->connectionName ?? config('database.default');
                $connection = config("database.connections.{$connectionName}");
                
                // Extract table name from SQL query
                $tableName = null;
                $sql = strtolower(trim($query->sql));
                
                // Match common SQL patterns to extract table name
                if (preg_match('/(?:from|into|update|join)\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query->sql, $matches)) {
                    $tableName = $matches[1];
                } elseif (preg_match('/(?:table\s+)`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $query->sql, $matches)) {
                    $tableName = $matches[1];
                }
                
                $spanBuilder = $tracer->spanBuilder('db.query')
                    ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, $connection['driver'] ?? 'unknown')
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_NAME, $connection['database'] ?? $connectionName)
                    ->setAttribute('server.address', $connection['host'] ?? 'localhost')
                    ->setAttribute('server.port', $connection['port'] ?? 3306)
                    ->setAttribute('db.statement', $query->sql)
                    ->setAttribute('db.query.duration_ms', $query->time);
                
                // Add SQL parameter bindings if they exist
                if (!empty($query->bindings)) {
                    $spanBuilder->setAttribute('db.statement.parameters', json_encode($query->bindings));
                    $spanBuilder->setAttribute('db.statement.parameters.count', count($query->bindings));
                }
                
                // Add table name if extracted
                if ($tableName) {
                    $spanBuilder->setAttribute('db.sql.table', $tableName);
                }
                
                $span = $spanBuilder->startSpan();
                $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
                $span->end();
                
            } catch (\Throwable $e) {
                // Silently fail
            }
        });

        // Add queue event listeners for Redis queue tracking
        \Illuminate\Support\Facades\Queue::before(function (\Illuminate\Queue\Events\JobProcessing $event) use ($tracer) {
            if (!$tracer) {
                return;
            }
            
            try {
                $job = $event->job;
                $payload = $job->payload();
                $queueDriver = config('queue.default', 'sync');
                
                // Extract trace context from job payload if available
                $parentContext = \OpenTelemetry\Context\Context::getCurrent();
                if (isset($payload['data']['traceContext'])) {
                    try {
                        $parentContext = \OpenTelemetry\API\Trace\Propagation\TraceContextPropagator::getInstance()
                            ->extract($payload['data']['traceContext']);
                    } catch (\Throwable $e) {
                        // Fall back to current context
                    }
                }
                
                $spanBuilder = $tracer->spanBuilder('queue.job.receive')
                    ->setSpanKind(SpanKind::KIND_CONSUMER)
                    ->setAttribute('messaging.system', $queueDriver === 'redis' ? 'redis' : $queueDriver)
                    ->setAttribute('messaging.operation', 'receive')
                    ->setAttribute('queue.job.class', $payload['displayName'] ?? 'unknown')
                    ->setAttribute('queue.name', $event->job->getQueue() ?? 'default')
                    ->setAttribute('queue.job.id', $job->getJobId())
                    ->setAttribute('queue.job.attempts', $job->attempts());
                
                // Link to parent span
                if ($parentContext !== \OpenTelemetry\Context\Context::getCurrent()) {
                    $spanBuilder->setParent($parentContext);
                }
                
                $span = $spanBuilder->startSpan();
                
                // Store span in job for later completion
                $job->span = $span;
                
            } catch (\Throwable $e) {
                // Silently fail
            }
        });

        \Illuminate\Support\Facades\Queue::after(function (\Illuminate\Queue\Events\JobProcessed $event) {
            try {
                $job = $event->job;
                if (isset($job->span)) {
                    $job->span->setStatus(StatusCode::STATUS_OK);
                    $job->span->end();
                    unset($job->span);
                }
            } catch (\Throwable $e) {
                // Silently fail
            }
        });

        \Illuminate\Support\Facades\Queue::failing(function (\Illuminate\Queue\Events\JobFailed $event) {
            try {
                $job = $event->job;
                if (isset($job->span)) {
                    $job->span->setStatus(StatusCode::STATUS_ERROR, $event->exception->getMessage());
                    $job->span->recordException($event->exception);
                    $job->span->end();
                    unset($job->span);
                }
            } catch (\Throwable $e) {
                // Silently fail
            }
        });
    }
}
