<?php

use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Route;

Route::get('/auto/redis/test', function () {
    $results = [];
    
    try {
        // Test automatic Redis instrumentation using auto_redis() helper
        $redis = auto_redis();
        $key = 'auto:test:' . uniqid();
        
        // These should automatically be traced without using traced_* functions
        $redis->set($key, 'auto_instrumented_value');
        $value = $redis->get($key);
        $deleted = $redis->del($key);
        
        $results['auto_redis'] = [
            'status' => 'success',
            'message' => 'Automatic Redis instrumentation test',
            'operations' => ['SET', 'GET', 'DEL'],
            'test_value' => $value,
            'deleted_keys' => $deleted
        ];
        
        // Test hash operations
        $hashKey = 'auto:hash:' . uniqid();
        $redis->hset($hashKey, 'name', 'Auto Test User');
        $redis->hset($hashKey, 'email', 'auto@test.com');
        $name = $redis->hget($hashKey, 'name');
        $all = $redis->hgetall($hashKey);
        $redis->del($hashKey);
        
        $results['auto_redis_hash'] = [
            'status' => 'success',
            'operations' => ['HSET', 'HGET', 'HGETALL', 'DEL'],
            'name' => $name,
            'all_data' => $all
        ];
        
        // Test list operations
        $listKey = 'auto:list:' . uniqid();
        $redis->lpush($listKey, 'item1');
        $redis->lpush($listKey, 'item2');
        $length = $redis->llen($listKey);
        $items = $redis->lrange($listKey, 0, -1);
        $redis->del($listKey);
        
        $results['auto_redis_list'] = [
            'status' => 'success',
            'operations' => ['LPUSH', 'LLEN', 'LRANGE', 'DEL'],
            'length' => $length,
            'items' => $items
        ];
        
    } catch (Exception $e) {
        $results['auto_redis'] = [
            'status' => 'error',
            'message' => $e->getMessage()
        ];
    }
    
    return response()->json($results);
});

Route::get('/auto/redis/job-test', function () {
    try {
        // Create a simple job that uses Redis facade directly
        $jobClass = new class {
            public function handle() {
                $redis = auto_redis();
                $key = 'job:auto:' . uniqid();
                
                // These Redis calls should be automatically traced
                $redis->set($key, json_encode([
                    'job_id' => uniqid(),
                    'processed_at' => time(),
                    'status' => 'processing'
                ]));
                
                $data = json_decode($redis->get($key), true);
                $data['status'] = 'completed';
                
                $redis->set($key, json_encode($data));
                
                // Clean up
                $redis->del($key);
                
                return $data;
            }
        };
        
        // Execute the job directly to test Redis auto-instrumentation
        $result = $jobClass->handle();
        
        return response()->json([
            'status' => 'success',
            'message' => 'Job with automatic Redis instrumentation completed',
            'job_result' => $result,
            'note' => 'All Redis operations should be automatically traced'
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => $e->getMessage()
        ], 500);
    }
});

Route::get('/auto/redis/performance', function () {
    $operations = [];
    $startTime = microtime(true);
    
    try {
        // Test multiple Redis operations for performance measurement
        $redis = auto_redis();
        for ($i = 1; $i <= 10; $i++) {
            $key = "perf:test:$i";
            
            $redis->set($key, "value_$i");
            $value = $redis->get($key);
            $redis->del($key);
            
            $operations[] = [
                'iteration' => $i,
                'key' => $key,
                'value_retrieved' => $value
            ];
        }
        
        $endTime = microtime(true);
        $totalTime = ($endTime - $startTime) * 1000;
        
        return response()->json([
            'status' => 'success',
            'message' => 'Performance test with automatic Redis instrumentation',
            'total_operations' => count($operations) * 3, // SET, GET, DEL per iteration
            'execution_time_ms' => round($totalTime, 2),
            'operations_per_ms' => round((count($operations) * 3) / $totalTime, 2),
            'note' => 'All Redis operations automatically traced with minimal overhead'
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => $e->getMessage()
        ], 500);
    }
});