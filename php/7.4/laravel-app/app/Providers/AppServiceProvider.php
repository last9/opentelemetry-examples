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
                if (isset($GLOBALS['official_simple_tracer'])) {
                    $GLOBALS['official_simple_tracer']->traceDatabase(
                        $sql,
                        $query->connectionName ?? null,
                        null,
                        $query->time,
                        null,
                        null
                    );
                }
            } catch (\Throwable $e) {
                // Silently fail - tracing should not break the application
            }
        });

        // Enable query logging for Eloquent event tracing
        \Illuminate\Support\Facades\DB::enableQueryLog();

        // OpenTelemetry: Trace Eloquent model events with actual SQL
        \Illuminate\Support\Facades\Event::listen([
            'eloquent.retrieved: *',
            'eloquent.created: *',
            'eloquent.updated: *',
            'eloquent.deleted: *',
            'eloquent.saved: *',
            'eloquent.restored: *',
        ], function ($eventName, $models) {
            if (isset($GLOBALS['official_simple_tracer'])) {
                $modelClass = get_class($models[0]);
                $operation = str_replace('eloquent.', '', explode(':', $eventName)[0]);
                $queryLog = \Illuminate\Support\Facades\DB::getQueryLog();
                if (!empty($queryLog)) {
                    $lastQuery = end($queryLog);
                    $sql = $lastQuery['query'] ?? "Eloquent {$operation}: {$modelClass}";
                    $bindings = $lastQuery['bindings'] ?? [];
                    foreach ($bindings as $binding) {
                        if ($binding instanceof \DateTimeInterface) {
                            $binding = $binding->format('Y-m-d H:i:s');
                        } elseif (is_bool($binding)) {
                            $binding = $binding ? '1' : '0';
                        } elseif (is_null($binding)) {
                            $binding = 'NULL';
                        } elseif (is_numeric($binding)) {
                            $binding = (string)$binding;
                        } else {
                            $binding = (string)$binding;
                        }
                        $sql = preg_replace('/\?/', "'" . addslashes($binding) . "'", $sql, 1);
                    }
                    // Create a different span name for Eloquent events to distinguish from DB::listen
                    $spanName = "eloquent.{$operation}.{$modelClass}";
                    $GLOBALS['official_simple_tracer']->traceDatabase(
                        $sql,
                        $modelClass, // dbName
                        $lastQuery['connection'] ?? null, // connectionName
                        $lastQuery['time'] ?? null, // duration
                        count($models), // rowCount
                        null, // error
                        $spanName // custom span name
                    );
                }
            }
        });
    }
}
