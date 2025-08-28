<?php

require_once __DIR__ . '/bootstrap/otel.php';

use App\Jobs\ExampleTracedJob;

$app = require_once __DIR__ . '/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

echo "Testing Queue Worker with Redis instrumentation...\n\n";

// Dispatch some jobs first
echo "1. Dispatching test jobs to Redis queue:\n";
for ($i = 1; $i <= 3; $i++) {
    try {
        $jobData = [
            'job_number' => $i,
            'test_type' => 'queue_worker_test',
            'timestamp' => time(),
            'data' => "Test job #$i for Redis queue processing"
        ];
        
        traced_queue_push(new ExampleTracedJob($jobData));
        echo "   - Job #$i dispatched successfully\n";
        
    } catch (Exception $e) {
        echo "   - Job #$i failed: " . $e->getMessage() . "\n";
    }
}

echo "\n2. Processing queue jobs (simulating worker):\n";
echo "   Note: In production, run 'php artisan queue:work redis' to process jobs\n";
echo "   For this test, we'll manually process jobs from the queue:\n\n";

try {
    $queueManager = app('queue');
    $connection = $queueManager->connection('redis');
    
    // Process a few jobs manually to demonstrate tracing
    for ($i = 1; $i <= 3; $i++) {
        echo "   Processing job #$i:\n";
        
        $job = $connection->pop('default');
        if ($job) {
            echo "     - Job found: " . $job->getName() . "\n";
            echo "     - Job ID: " . $job->getJobId() . "\n";
            echo "     - Attempts: " . $job->attempts() . "\n";
            
            try {
                $job->fire();
                echo "     - Job completed successfully\n";
            } catch (Exception $e) {
                echo "     - Job failed: " . $e->getMessage() . "\n";
                $job->failed($e);
            }
        } else {
            echo "     - No job available\n";
            break;
        }
        
        echo "\n";
    }
    
} catch (Exception $e) {
    echo "   - Queue processing error: " . $e->getMessage() . "\n";
}

echo "Queue worker test completed!\n";
echo "Check your Last9 dashboard for queue processing traces.\n";