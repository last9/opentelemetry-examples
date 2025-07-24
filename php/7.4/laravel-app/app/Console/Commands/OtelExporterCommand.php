<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

class OtelExporterCommand extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'otel:exporter 
                            {action : Action to perform (status, flush, config)}
                            {--force : Force the action}';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Manage OpenTelemetry official SDK exporter';

    /**
     * Execute the console command.
     *
     * @return int
     */
    public function handle()
    {
        $action = $this->argument('action');
        
        switch ($action) {
            case 'status':
                return $this->showStatus();
            case 'flush':
                return $this->flushBuffer();
            case 'config':
                return $this->showConfig();
            default:
                $this->error("Unknown action: {$action}");
                $this->info("Available actions: status, flush, config");
                return 1;
        }
    }
    
    /**
     * Show exporter status
     */
    private function showStatus()
    {
        if (!isset($GLOBALS['official_batch_processor'])) {
            $this->error('❌ Official OpenTelemetry SDK batch processor not available');
            return 1;
        }
        
        $this->info('OpenTelemetry Official SDK Batch Span Processor Status');
        $this->info('=====================================================');
        
        $this->table(
            ['Setting', 'Value'],
            [
                ['Service Name', env('OTEL_SERVICE_NAME', 'laravel-app')],
                ['Service Version', env('OTEL_SERVICE_VERSION', '1.0.0')],
                ['Collector Endpoint', env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'http://localhost:4318/v1/traces')],
                ['Protocol', env('OTEL_EXPORTER_OTLP_PROTOCOL', 'http/protobuf')],
                ['Max Export Batch Size', env('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', 2048)],
                ['Max Queue Size', env('OTEL_BSP_MAX_QUEUE_SIZE', 2048)],
                ['Scheduled Delay', env('OTEL_BSP_SCHEDULED_DELAY_MS', 5000) . ' ms'],
                ['Export Timeout', env('OTEL_BSP_EXPORT_TIMEOUT_MS', 30000) . ' ms'],
                ['Max Concurrent Exports', env('OTEL_BSP_MAX_CONCURRENT_EXPORTS', 1)],
            ]
        );
        
        // Show OpenTelemetry SDK compliance
        $this->info("\n📋 OpenTelemetry SDK Compliance:");
        $this->info("✅ Using official OpenTelemetry PHP SDK");
        $this->info("✅ Using standard Batch Span Processor");
        $this->info("✅ Following OpenTelemetry SDK specifications");
        
        return 0;
    }
    
    /**
     * Force flush the buffer
     */
    private function flushBuffer()
    {
        if (!isset($GLOBALS['official_batch_processor'])) {
            $this->error('❌ Official OpenTelemetry SDK batch processor not available');
            return 1;
        }
        
        $this->info('🔄 Forcing flush of OpenTelemetry batch processor...');
        
        try {
            $flushResult = $GLOBALS['official_batch_processor']->forceFlush();
            
            if ($flushResult) {
                $this->info('✅ Flush completed successfully');
            } else {
                $this->warn('⚠️  Flush completed but may not have been successful');
            }
            
            return 0;
        } catch (\Exception $e) {
            $this->error('❌ Flush failed: ' . $e->getMessage());
            return 1;
        }
    }
    
    /**
     * Show configuration
     */
    private function showConfig()
    {
        $this->info('OpenTelemetry Official SDK Configuration');
        $this->info('========================================');
        
        $config = [
            'service' => [
                'name' => env('OTEL_SERVICE_NAME', 'laravel-app'),
                'version' => env('OTEL_SERVICE_VERSION', '1.0.0'),
            ],
            'exporter' => [
                'endpoint' => env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'http://localhost:4318/v1/traces'),
                'headers' => env('OTEL_EXPORTER_OTLP_HEADERS', ''),
                'protocol' => env('OTEL_EXPORTER_OTLP_PROTOCOL', 'http/protobuf'),
            ],
            'batch_span_processor' => [
                'max_export_batch_size' => env('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', 2048),
                'max_queue_size' => env('OTEL_BSP_MAX_QUEUE_SIZE', 2048),
                'scheduled_delay_ms' => env('OTEL_BSP_SCHEDULED_DELAY_MS', 5000),
                'export_timeout_ms' => env('OTEL_BSP_EXPORT_TIMEOUT_MS', 30000),
                'max_concurrent_exports' => env('OTEL_BSP_MAX_CONCURRENT_EXPORTS', 1),
            ],
        ];
        
        $this->info('Service Configuration:');
        $this->table(
            ['Setting', 'Value'],
            [
                ['Service Name', $config['service']['name']],
                ['Service Version', $config['service']['version']],
            ]
        );
        
        $this->info('Exporter Configuration:');
        $this->table(
            ['Setting', 'Value'],
            [
                ['Endpoint', $config['exporter']['endpoint']],
                ['Protocol', $config['exporter']['protocol']],
                ['Headers', $config['exporter']['headers'] ?: 'None'],
            ]
        );
        
        $this->info('Batch Span Processor Configuration:');
        $this->table(
            ['Setting', 'Value', 'SDK Default'],
            [
                ['Max Export Batch Size', $config['batch_span_processor']['max_export_batch_size'], '2048'],
                ['Max Queue Size', $config['batch_span_processor']['max_queue_size'], '2048'],
                ['Scheduled Delay', $config['batch_span_processor']['scheduled_delay_ms'] . ' ms', '5000 ms'],
                ['Export Timeout', $config['batch_span_processor']['export_timeout_ms'] . ' ms', '30000 ms'],
                ['Max Concurrent Exports', $config['batch_span_processor']['max_concurrent_exports'], '1'],
            ]
        );
        
        return 0;
    }
} 