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
        // OpenTelemetry: Trace all database queries
        \Illuminate\Support\Facades\DB::listen(function ($query) {
            try {
                $sql = $query->sql;
                if (!empty($query->bindings)) {
                    foreach ($query->bindings as $binding) {
                        if ($binding instanceof \DateTimeInterface) {
                            $binding = $binding->format('Y-m-d H:i:s');
                        } elseif (is_bool($binding)) {
                            $binding = $binding ? '1' : '0';
                        } elseif (is_null($binding)) {
                            $binding = 'NULL';
                        } elseif (!is_numeric($binding)) {
                            $binding = (string)$binding;
                        }
                        $sql = preg_replace('/\?/', "'" . addslashes($binding) . "'", $sql, 1);
                    }
                }
                if (isset($GLOBALS['official_tracer'])) {
                    $operation = 'query';
                    $tableName = null;
                    
                    // Extract operation and table name
                    $queryUpper = trim(strtoupper($sql));
                    if (preg_match('/^(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE|REPLACE|SHOW|DESCRIBE|EXPLAIN)/', $queryUpper, $matches)) {
                        $operation = strtolower($matches[1]);
                    }
                    
                    // Extract table name based on operation
                    switch ($operation) {
                        case 'select':
                            if (preg_match('/\bFROM\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $sql, $matches)) {
                                $tableName = $matches[1];
                            }
                            break;
                        case 'insert':
                            if (preg_match('/\bINTO\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $sql, $matches)) {
                                $tableName = $matches[1];
                            }
                            break;
                        case 'update':
                            if (preg_match('/\bUPDATE\s+`?([a-zA-Z_][a-zA-Z0-9_]*)`?/i', $sql, $matches)) {
                                $tableName = $matches[1];
                            }
                            break;
                        case 'delete':
                            if (preg_match('/\bFROM\s+`?([a-zA-Z0-9_]*)`?/i', $sql, $matches)) {
                                $tableName = $matches[1];
                            }
                            break;
                    }
                    
                    $spanName = 'db.' . $operation . ($tableName ? " {$tableName}" : '');
                    
                    // Get current span context for parent-child relationship
                    $currentSpan = \OpenTelemetry\API\Trace\Span::getCurrent();
                    $spanContext = $currentSpan->getContext();
                    
                    $span = $GLOBALS['official_tracer']->spanBuilder($spanName)
                        ->setSpanKind(\OpenTelemetry\API\Trace\SpanKind::KIND_CLIENT)
                        ->setAttribute('db.system', 'mysql')
                        ->setAttribute('db.statement', $sql)
                        ->setAttribute('db.operation', $operation)
                        ->setAttribute('db.name', $query->connectionName ?? 'laravel')
                        ->setAttribute('server.address', 'mysql')
                        ->setAttribute('server.port', 3306)
                        ->setAttribute('network.transport', 'tcp')
                        ->setAttribute('network.type', 'ipv4');
                    
                    // Set parent context if we have a current span
                    if ($spanContext->isValid()) {
                        $span->setParent(\OpenTelemetry\Context\Context::getCurrent());
                    }
                    
                    // Start the span - SDK will automatically capture start time
                    $span = $span->startSpan();
                    
                    if ($tableName) {
                        $span->setAttribute('db.sql.table', $tableName);
                    }
                    
                    // Simulate the actual query duration
                    if ($query->time > 0) {
                        usleep($query->time * 1000); // Convert ms to microseconds
                    }
                    
                    $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_OK);
                    $span->end();
                }
            } catch (\Throwable $e) {
                // Silently fail - tracing should not break the application
            }
        });


    }
}
