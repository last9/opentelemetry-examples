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
        // Capture tracer reference outside closure to avoid scope issues
        $tracer = $GLOBALS['otel_tracer'] ?? null;
        
        // Optimized OpenTelemetry database query tracing using official SDK patterns
        \Illuminate\Support\Facades\DB::listen(function ($query) use ($tracer) {
            // Early return if tracer not available to minimize overhead
            if (!$tracer) {
                return;
            }
            
            try {
                // Create span with standard attributes and ensure it's properly parented
                $spanBuilder = $tracer->spanBuilder('db.query')
                    ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, 'mysql')
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_NAME, $query->connectionName ?? 'laravel')
                    ->setAttribute('server.address', 'localhost')
                    ->setAttribute('server.port', 3306)
                    ->setAttribute('db.statement', $query->sql)
                    ->setAttribute('db.query.duration_ms', $query->time)
                    ->setAttribute('db.query.timing', 'post_execution');
                
                // Check if there's an active span to use as parent
                $activeSpan = \OpenTelemetry\API\Trace\Span::getCurrent();
                if ($activeSpan && $activeSpan->getContext()->isValid()) {
                    $spanBuilder->setParent($activeSpan->getContext());
                }
                
                $span = $spanBuilder->startSpan();
                $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
                $span->end();
                
            } catch (\Throwable $e) {
                // Silently fail - tracing should not break the application
            }
        });
    }
}
