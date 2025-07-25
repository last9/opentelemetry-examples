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
    }
}
