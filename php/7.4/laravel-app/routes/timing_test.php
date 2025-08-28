<?php

// Add this route to web.php for detailed timing verification
Route::get('/test-db-timing-detailed', function () {
    $results = [];
    
    // Test 1: Simple SELECT with timing measurement
    $start = microtime(true);
    try {
        $users = DB::select('SELECT 1 as test');
        $actualDuration = (microtime(true) - $start) * 1000; // Convert to ms
        $results['simple_select'] = [
            'query' => 'SELECT 1 as test',
            'actual_duration_ms' => round($actualDuration, 3),
            'result_count' => count($users),
            'success' => true
        ];
    } catch (Exception $e) {
        $results['simple_select'] = [
            'query' => 'SELECT 1 as test',
            'error' => $e->getMessage(),
            'success' => false
        ];
    }
    
    // Test 2: COUNT query with timing
    $start = microtime(true);
    try {
        $count = DB::select('SELECT COUNT(*) as count FROM users');
        $actualDuration = (microtime(true) - $start) * 1000;
        $results['count_query'] = [
            'query' => 'SELECT COUNT(*) as count FROM users',
            'actual_duration_ms' => round($actualDuration, 3),
            'count' => $count[0]->count ?? 0,
            'success' => true
        ];
    } catch (Exception $e) {
        $results['count_query'] = [
            'query' => 'SELECT COUNT(*) as count FROM users',
            'error' => $e->getMessage(),
            'success' => false
        ];
    }
    
    // Test 3: Multiple queries to check consistency
    $timings = [];
    for ($i = 0; $i < 5; $i++) {
        $start = microtime(true);
        try {
            DB::select('SELECT ? as iteration', [$i]);
            $timings[] = round((microtime(true) - $start) * 1000, 3);
        } catch (Exception $e) {
            $timings[] = 'ERROR: ' . $e->getMessage();
        }
    }
    
    $results['multiple_queries'] = [
        'query' => 'SELECT ? as iteration (5 times)',
        'individual_timings_ms' => $timings,
        'avg_timing_ms' => is_numeric($timings[0]) ? round(array_sum($timings) / count($timings), 3) : 'N/A',
        'min_timing_ms' => is_numeric($timings[0]) ? min($timings) : 'N/A',
        'max_timing_ms' => is_numeric($timings[0]) ? max($timings) : 'N/A'
    ];
    
    // Force flush spans
    $flushResult = false;
    if (isset($GLOBALS['otel_batch_processor'])) {
        $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
    }
    
    return response()->json([
        'message' => 'Database timing verification completed',
        'timing_tests' => $results,
        'flush_result' => $flushResult,
        'note' => 'Compare actual_duration_ms with span attributes in your telemetry backend',
        'timestamp' => now()->toISOString()
    ]);
});