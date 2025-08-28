<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;

/*
|--------------------------------------------------------------------------
| Console Routes
|--------------------------------------------------------------------------
|
| This file is where you may define all of your Closure based console
| commands. Each Closure is bound to a command instance allowing a
| simple approach to interacting with each command's IO methods.
|
*/

Artisan::command('test:db-spans', function () {
    $this->info('🔍 TESTING DATABASE SPAN GENERATION');
    $this->info('=====================================');
    $this->newLine();

    // Test 1: Simple SELECT query
    $this->info('1. Testing SELECT query...');
    try {
        $users = DB::select('SELECT COUNT(*) as count FROM users');
        $this->info('   ✅ Query executed successfully, count: ' . ($users[0]->count ?? 0));
    } catch (Exception $e) {
        $this->error('   ❌ Query failed: ' . $e->getMessage());
    }

    // Test 2: INSERT query  
    $this->newLine();
    $this->info('2. Testing INSERT query...');
    try {
        DB::insert(
            'INSERT INTO users (name, email, password, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
            ['Test User ' . time(), 'test' . time() . '@example.com', 'password', date('Y-m-d H:i:s'), date('Y-m-d H:i:s')]
        );
        $this->info('   ✅ INSERT executed successfully');
    } catch (Exception $e) {
        $this->error('   ❌ INSERT failed: ' . $e->getMessage());
    }

    // Test 3: UPDATE query
    $this->newLine();
    $this->info('3. Testing UPDATE query...');
    try {
        $affected = DB::update(
            'UPDATE users SET updated_at = ? WHERE email LIKE ?',
            [date('Y-m-d H:i:s'), '%example.com']
        );
        $this->info('   ✅ UPDATE executed successfully, affected rows: ' . $affected);
    } catch (Exception $e) {
        $this->error('   ❌ UPDATE failed: ' . $e->getMessage());
    }

    // Force flush to ensure spans are sent
    $this->newLine();
    $this->info('4. Flushing spans...');
    if (isset($GLOBALS['otel_batch_processor'])) {
        $flushResult = $GLOBALS['otel_batch_processor']->forceFlush();
        $this->info('   ✅ Flush result: ' . ($flushResult ? 'SUCCESS' : 'FAILED'));
    } else {
        $this->warn('   ⚠️  Batch processor not available');
    }

    $this->newLine();
    $this->info('🎯 Database span testing completed!');
    $this->info('Check your OpenTelemetry collector/backend for the generated spans.');
})->purpose('Test database span generation');