<?php

use App\Jobs\ExampleTracedJob;
use Illuminate\Support\Facades\Route;

Route::get('/redis/test', function () {
    $results = [];
    
    // Test Redis operations (fallback to cache if Redis not available)
    try {
        if (extension_loaded('redis')) {
            $key = 'test:web:' . uniqid();
            traced_redis_set($key, 'web_test_value', 60);
            $value = traced_redis_get($key);
            traced_redis_del($key);
            
            $results['redis'] = [
                'status' => 'success',
                'operations' => ['SET', 'GET', 'DEL'],
                'test_value' => $value
            ];
        } else {
            // Fallback to file cache for demonstration
            $key = 'test_cache_key';
            cache()->put($key, 'fallback_value', 60);
            $value = cache()->get($key);
            cache()->forget($key);
            
            $results['redis'] = [
                'status' => 'fallback_cache',
                'message' => 'Redis extension not available, used Laravel cache',
                'operations' => ['PUT', 'GET', 'FORGET'],
                'test_value' => $value
            ];
        }
    } catch (Exception $e) {
        $results['redis'] = [
            'status' => 'error',
            'message' => $e->getMessage()
        ];
    }
    
    // Test Queue operations (will use database queue if Redis not available)
    try {
        traced_queue_push(new ExampleTracedJob(['source' => 'web_route', 'timestamp' => time()]));
        
        $results['queue'] = [
            'status' => 'success',
            'message' => 'Job dispatched to queue (driver: ' . config('queue.default') . ')',
            'queue_driver' => config('queue.default')
        ];
    } catch (Exception $e) {
        $results['queue'] = [
            'status' => 'error',
            'message' => $e->getMessage()
        ];
    }
    
    return response()->json($results);
});

Route::get('/redis/queue/dispatch/{count?}', function ($count = 1) {
    $dispatched = [];
    
    for ($i = 0; $i < $count; $i++) {
        try {
            traced_queue_push(new ExampleTracedJob([
                'batch_id' => uniqid(),
                'item_number' => $i + 1,
                'total_items' => $count,
                'timestamp' => time()
            ]));
            
            $dispatched[] = ['item' => $i + 1, 'status' => 'dispatched'];
        } catch (Exception $e) {
            $dispatched[] = ['item' => $i + 1, 'status' => 'error', 'message' => $e->getMessage()];
        }
    }
    
    return response()->json([
        'total_dispatched' => count(array_filter($dispatched, fn($item) => $item['status'] === 'dispatched')),
        'jobs' => $dispatched
    ]);
});