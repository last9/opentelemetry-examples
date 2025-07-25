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
        // Optimized OpenTelemetry database query tracing using official SDK patterns
        \Illuminate\Support\Facades\DB::listen(function ($query) {
            // Early return if tracer not available to minimize overhead
            if (!isset($GLOBALS['otel_tracer'])) {
                return;
            }
            
            try {
                // Minimal database span creation - no regex parsing or sensitive filtering
                $spanBuilder = $GLOBALS['otel_tracer']->spanBuilder('db.query')
                    ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, 'mysql')
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_NAME, $query->connectionName ?? 'laravel')
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::SERVER_ADDRESS, 'localhost')
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::SERVER_PORT, 3306);
                
                // Add query duration if available
                if ($query->time > 0) {
                    $spanBuilder->setAttribute('db.query.duration', $query->time);
                }
                
                // Create and immediately end span
                $span = $spanBuilder->startSpan();
                $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
                $span->end();
                
            } catch (\Throwable $e) {
                // Silently fail - tracing should not break the application
            }
        });
    }
}
