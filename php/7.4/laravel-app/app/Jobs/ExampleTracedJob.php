<?php

namespace App\Jobs;

use Illuminate\Support\Facades\Log;

class ExampleTracedJob extends BaseTracedJob
{
    protected $data;

    public function __construct($data = [])
    {
        $this->data = $data;
    }

    public function handleJob()
    {
        Log::info('Processing traced job', ['data' => $this->data]);
        
        // Simulate some work with Redis operations
        traced_redis_set('job_status:' . uniqid(), 'processing');
        
        // Simulate work
        sleep(1);
        
        // Update status
        traced_redis_set('job_status:' . uniqid(), 'completed');
        
        return ['status' => 'completed', 'processed_data' => $this->data];
    }
}