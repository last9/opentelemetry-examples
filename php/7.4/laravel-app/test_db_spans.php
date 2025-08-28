<?php

// Test script to verify database spans are being generated correctly
require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/bootstrap/otel.php';

// Initialize Laravel application
$app = require_once __DIR__ . '/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

// Set up the application facade
\Illuminate\Container\Container::setInstance($app);
\Illuminate\Support\Facades\Facade::setFacadeApplication($app);

echo "🔍 TESTING DATABASE SPAN GENERATION\n";
echo "=====================================\n\n";

// Test 1: Simple SELECT query
echo "1. Testing SELECT query...\n";
try {
    $users = \Illuminate\Support\Facades\DB::select('SELECT COUNT(*) as count FROM users');
    echo "   ✅ Query executed successfully, count: " . ($users[0]->count ?? 0) . "\n";
} catch (Exception $e) {
    echo "   ❌ Query failed: " . $e->getMessage() . "\n";
}

// Test 2: INSERT query  
echo "\n2. Testing INSERT query...\n";
try {
    \Illuminate\Support\Facades\DB::insert(
        'INSERT INTO users (name, email, password, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Test User ' . time(), 'test' . time() . '@example.com', 'password', date('Y-m-d H:i:s'), date('Y-m-d H:i:s')]
    );
    echo "   ✅ INSERT executed successfully\n";
} catch (Exception $e) {
    echo "   ❌ INSERT failed: " . $e->getMessage() . "\n";
}

// Test 3: UPDATE query
echo "\n3. Testing UPDATE query...\n";
try {
    $affected = \Illuminate\Support\Facades\DB::update(
        'UPDATE users SET updated_at = ? WHERE email LIKE ?',
        [date('Y-m-d H:i:s'), '%example.com']
    );
    echo "   ✅ UPDATE executed successfully, affected rows: $affected\n";
} catch (Exception $e) {
    echo "   ❌ UPDATE failed: " . $e->getMessage() . "\n";
}

// Force flush to ensure spans are sent
echo "\n4. Flushing spans...\n";
if (isset($GLOBALS['otel_batch_processor'])) {
    $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
    echo "   ✅ Flush result: " . ($flushResult ? 'SUCCESS' : 'FAILED') . "\n";
} else {
    echo "   ⚠️  Batch processor not available\n";
}

echo "\n🎯 Database span testing completed!\n";
echo "Check your OpenTelemetry collector/backend for the generated spans.\n";