<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SemConv\ResourceAttributes;

class OpenTelemetryServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->singleton(TracerProvider::class, function ($app) {
            $attributes = Attributes::create([
                ResourceAttributes::SERVICE_NAME => env('OTEL_SERVICE_NAME', config('app.name', 'Lumen App')),
                ResourceAttributes::SERVICE_VERSION => env('APP_VERSION', '1.0.0'),
                'deployment.environment' => config('app.env', 'local'),
            ]);
            
            $resource = ResourceInfo::create($attributes);

            // Get OTLP endpoint from environment (standard OpenTelemetry variable)
            $otlpEndpoint = env('OTEL_EXPORTER_OTLP_ENDPOINT', env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'https://otlp-aps1.last9.io:443/v1/traces'));
            
            // Get authorization from environment
            $authHeader = env('OTEL_EXPORTER_OTLP_HEADERS');
            
            if (!$authHeader) {
                throw new \Exception('OTEL_EXPORTER_OTLP_HEADERS environment variable is required for OpenTelemetry configuration');
            }
            
            $authValue = str_replace('Authorization=', '', $authHeader);
            
            $headers = [
                'Authorization' => $authValue,
                'Content-Type' => 'application/json'
            ];
            
            $transport = (new OtlpHttpTransportFactory())->create(
                $otlpEndpoint,
                'application/json',
                $headers
            );
            
            $exporter = new SpanExporter($transport);
            $spanProcessor = new SimpleSpanProcessor($exporter);

            return new TracerProvider([$spanProcessor], null, $resource);
        });

        $this->app->singleton(TracerInterface::class, function ($app) {
            $tracerProvider = $app->make(TracerProvider::class);
            return $tracerProvider->getTracer(env('OTEL_SERVICE_NAME', 'lumen-app'));
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Initialize auto-instrumentation
        $this->initializeAutoInstrumentation();
    }

    private function initializeAutoInstrumentation(): void
    {
        // Laravel auto-instrumentation
        if (class_exists('OpenTelemetry\Contrib\Instrumentation\Laravel\LaravelInstrumentation')) {
            \OpenTelemetry\Contrib\Instrumentation\Laravel\LaravelInstrumentation::register();
        }

        // PDO auto-instrumentation for database queries
        if (class_exists('OpenTelemetry\Contrib\Instrumentation\PDO\PDOInstrumentation')) {
            \OpenTelemetry\Contrib\Instrumentation\PDO\PDOInstrumentation::register();
        }

        // PSR-18 HTTP client auto-instrumentation
        if (class_exists('OpenTelemetry\Contrib\Instrumentation\Psr18\Psr18Instrumentation')) {
            \OpenTelemetry\Contrib\Instrumentation\Psr18\Psr18Instrumentation::register();
        }
    }
}
