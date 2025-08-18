<?php

use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Route;

Route::get('/transparent/redis/test', function () {
    $results = [];
    
    try {
        // Test transparent Redis instrumentation using standard Laravel Redis facade
        $key = 'transparent:test:' . uniqid();
        
        // These should automatically be traced without any code changes
        Redis::set($key, 'transparent_value');
        $value = Redis::get($key);
        $deleted = Redis::del($key);
        
        $results['transparent_redis'] = [
            'status' => 'success',
            'message' => 'Transparent Redis instrumentation - no code changes needed',
            'operations' => ['SET', 'GET', 'DEL'],
            'test_value' => $value,
            'deleted_keys' => $deleted
        ];
        
        // Test hash operations with standard Redis facade
        $hashKey = 'transparent:hash:' . uniqid();
        Redis::hset($hashKey, 'user_id', '123');
        Redis::hset($hashKey, 'session_data', json_encode(['login_time' => time()]));
        $userId = Redis::hget($hashKey, 'user_id');
        $sessionData = Redis::hget($hashKey, 'session_data');
        Redis::del($hashKey);
        
        $results['transparent_redis_hash'] = [
            'status' => 'success',
            'operations' => ['HSET', 'HGET', 'DEL'],
            'user_id' => $userId,
            'session_data' => json_decode($sessionData, true)
        ];
        
        // Test cache-like operations
        $cacheKey = 'transparent:cache:' . uniqid();
        Redis::setex($cacheKey, 300, 'cached_data');
        $cachedValue = Redis::get($cacheKey);
        $ttl = Redis::ttl($cacheKey);
        Redis::del($cacheKey);
        
        $results['transparent_redis_cache'] = [
            'status' => 'success',
            'operations' => ['SETEX', 'GET', 'TTL', 'DEL'],
            'cached_value' => $cachedValue,
            'ttl_seconds' => $ttl
        ];
        
    } catch (Exception $e) {
        $results['transparent_redis'] = [
            'status' => 'error',
            'message' => $e->getMessage()
        ];
    }
    
    return response()->json($results);
});

Route::get('/transparent/redis/job-simulation', function () {
    try {
        // Simulate job processing using standard Redis facade calls
        $jobId = uniqid();
        $jobKey = "job:$jobId";
        
        // Step 1: Mark job as started (should be automatically traced)
        Redis::hset($jobKey, 'status', 'started');
        Redis::hset($jobKey, 'started_at', time());
        
        // Step 2: Simulate processing with Redis operations
        Redis::hset($jobKey, 'status', 'processing');
        Redis::hset($jobKey, 'progress', '50');
        
        // Step 3: Store result data
        $resultData = ['processed_items' => 100, 'success_rate' => 98.5];
        Redis::hset($jobKey, 'result', json_encode($resultData));
        
        // Step 4: Mark as completed
        Redis::hset($jobKey, 'status', 'completed');
        Redis::hset($jobKey, 'completed_at', time());
        
        // Step 5: Get final job data
        $finalJobData = Redis::hgetall($jobKey);
        
        // Step 6: Clean up
        Redis::del($jobKey);
        
        return response()->json([
            'status' => 'success',
            'message' => 'Job simulation with transparent Redis instrumentation',
            'job_id' => $jobId,
            'final_job_data' => $finalJobData,
            'redis_operations_performed' => [
                'HSET (status, started_at, progress, result, completed_at)',
                'HGETALL (final data)',
                'DEL (cleanup)'
            ],
            'note' => 'All Redis operations automatically traced without code changes'
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'status' => 'error',
            'message' => $e->getMessage()
        ], 500);
    }
});