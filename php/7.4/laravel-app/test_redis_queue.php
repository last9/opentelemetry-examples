<?php

require_once __DIR__ . '/bootstrap/otel.php';
require_once __DIR__ . '/vendor/autoload.php';

use App\Jobs\ExampleTracedJob;

$app = require_once __DIR__ . '/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

echo "Testing Redis and Queue instrumentation...\n\n";

// Test Redis operations
echo "1. Testing Redis operations:\n";
try {
    echo "   - Setting key 'test:redis:key' with value 'hello_world'\n";
    $result = traced_redis_set('test:redis:key', 'hello_world', 300);
    echo "   - Redis SET result: " . ($result ? 'SUCCESS' : 'FAILED') . "\n";
    
    echo "   - Getting key 'test:redis:key'\n";
    $value = traced_redis_get('test:redis:key');
    echo "   - Redis GET result: " . $value . "\n";
    
    echo "   - Deleting key 'test:redis:key'\n";
    $deleted = traced_redis_del('test:redis:key');
    echo "   - Redis DEL result: " . $deleted . " key(s) deleted\n";
    
} catch (Exception $e) {
    echo "   - Redis error: " . $e->getMessage() . "\n";
}

echo "\n2. Testing Queue operations:\n";
try {
    echo "   - Dispatching ExampleTracedJob to Redis queue\n";
    $jobId = traced_queue_push(new ExampleTracedJob(['test_data' => 'redis_queue_test', 'timestamp' => time()]));
    echo "   - Job dispatched with ID: " . ($jobId ?? 'SUCCESS') . "\n";
    
    echo "   - Dispatching another job to specific queue 'high_priority'\n";
    $jobId2 = traced_queue_push(new ExampleTracedJob(['priority' => 'high', 'test_data' => 'priority_queue_test']), [], 'high_priority');
    echo "   - High priority job dispatched: " . ($jobId2 ?? 'SUCCESS') . "\n";
    
} catch (Exception $e) {
    echo "   - Queue error: " . $e->getMessage() . "\n";
}

echo "\n3. Testing direct Redis commands:\n";
try {
    $redis = app('redis')->connection();
    
    echo "   - Using traced_redis_command for HSET operation\n";
    $hsetResult = traced_redis_command($redis, 'hset', ['user:123', 'name', 'John Doe']);
    echo "   - HSET result: " . $hsetResult . "\n";
    
    echo "   - Using traced_redis_command for HGET operation\n";
    $hgetResult = traced_redis_command($redis, 'hget', ['user:123', 'name']);
    echo "   - HGET result: " . $hgetResult . "\n";
    
    echo "   - Using traced_redis_command for HDEL operation\n";
    $hdelResult = traced_redis_command($redis, 'hdel', ['user:123', 'name']);
    echo "   - HDEL result: " . $hdelResult . " field(s) deleted\n";
    
} catch (Exception $e) {
    echo "   - Direct Redis error: " . $e->getMessage() . "\n";
}

echo "\nRedis and Queue instrumentation test completed!\n";
echo "Check your Last9 dashboard for the generated traces.\n";