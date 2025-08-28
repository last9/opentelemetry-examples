<?php

namespace App\Providers;

use App\Http\Middleware\RedisInstrumentationWrapper;
use Illuminate\Redis\RedisManager;
use Illuminate\Support\ServiceProvider;

class RedisInstrumentationServiceProvider extends ServiceProvider
{
    public function register()
    {
        // Override the Redis manager binding to add automatic instrumentation
        $this->app->singleton('redis', function ($app) {
            $config = $app->make('config')->get('database.redis', []);
            
            return new class($app, $config) extends RedisManager {
                public function connection($name = null)
                {
                    $connection = parent::connection($name);
                    
                    // Only wrap if OpenTelemetry is available
                    if (isset($GLOBALS['otel_tracer'])) {
                        return new RedisInstrumentationWrapper($connection);
                    }
                    
                    return $connection;
                }
            };
        });
    }

    public function boot()
    {
        //
    }
}