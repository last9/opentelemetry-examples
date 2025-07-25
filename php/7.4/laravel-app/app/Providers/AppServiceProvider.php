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
                $span = $tracer->spanBuilder('db.query')
                    ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_SYSTEM, 'mysql')
                    ->setAttribute(\OpenTelemetry\SemConv\TraceAttributes::DB_NAME, $query->connectionName ?? 'laravel')
                    ->setAttribute('server.address', 'localhost')
                    ->setAttribute('server.port', 3306)
                    ->setAttribute('db.statement', $query->sql)
                    ->setAttribute('db.query.duration_ms', $query->time)
                    ->startSpan();
                
                $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
                $span->end();
                
            } catch (\Throwable $e) {
                // Silently fail
            }
        });
    }
}
