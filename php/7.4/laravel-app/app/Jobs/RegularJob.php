<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class RegularJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    protected $data;

    public function __construct($data = [])
    {
        $this->data = $data;
    }

    public function handle()
    {
        Log::info('Processing regular job (no BaseTracedJob)', ['data' => $this->data]);
        
        // Simulate some work with Redis operations
        \Illuminate\Support\Facades\Redis::set('regular_job_status:' . uniqid(), 'processing');
        
        // Simulate work
        sleep(1);
        
        // Update status
        \Illuminate\Support\Facades\Redis::set('regular_job_status:' . uniqid(), 'completed');
        
        Log::info('Regular job completed', ['data' => $this->data]);
        
        return ['status' => 'completed', 'processed_data' => $this->data];
    }
}