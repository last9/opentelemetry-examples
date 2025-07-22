<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\DB;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
|
| Here is where you can register web routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| contains the "web" middleware group. Now create something great!
|
*/

Route::get('/', function () {
    return response()->json([
        'message' => 'Laravel PHP 7.4 with OpenTelemetry',
        'timestamp' => date('Y-m-d H:i:s'),
        'php_version' => PHP_VERSION,
        'laravel_version' => app()->version()
    ]);
});

// Example routes showing OpenTelemetry tracing capabilities
Route::get('/api/health', function () {
    return response()->json([
        'status' => 'healthy',
        'timestamp' => date('Y-m-d H:i:s')
    ]);
});

// Test route to check if basic functionality works
Route::get('/api/test-debug', function () {
    file_put_contents('/tmp/test.log', "Test route called\n", FILE_APPEND);
    return response()->json(['message' => 'Test route working']);
});

Route::get('/api/example', function () {
    // Example of custom tracing in your application
    $GLOBALS['simple_tracer']->createTrace('business.logic', [
        'operation' => 'example_processing',
        'user_id' => 'anonymous'
    ]);
    
    return response()->json([
        'message' => 'Example endpoint with custom tracing',
        'traced' => true
    ]);
});

Route::get('/api/database-example', function () {
    // First test basic PHP functionality
    file_put_contents('/tmp/debug.log', "Route called at " . date('Y-m-d H:i:s') . "\n", FILE_APPEND);
    
    // Check if OpenTelemetry bootstrap was loaded
    file_put_contents('/tmp/debug.log', "SimpleTracer class exists: " . (class_exists('SimpleTracer') ? 'YES' : 'NO') . "\n", FILE_APPEND);
    
    // Example of database operation tracing with Eloquent ORM
    file_put_contents('/tmp/debug.log', "About to execute Eloquent query\n", FILE_APPEND);
    
    // Use Eloquent ORM instead of raw DB query
    $users = \App\User::where('email', 'like', '%@%')->limit(1)->get();
    
    // Debug: Check if tracer exists - use file_put_contents since error_log is disabled
    file_put_contents('/tmp/debug.log', "Tracer exists: " . (isset($GLOBALS['simple_tracer']) ? 'YES' : 'NO') . "\n", FILE_APPEND);
    
    // The DB::listen handler in AppServiceProvider will automatically trace this Eloquent query
    file_put_contents('/tmp/debug.log', "About to execute DB query\n", FILE_APPEND);
    
    // Also create a regular trace to test if spans work
    file_put_contents('/tmp/debug.log', "About to call createTrace\n", FILE_APPEND);
    if (isset($GLOBALS['simple_tracer'])) {
        $GLOBALS['simple_tracer']->createTrace('test.span', ['test' => 'value']);
    }
    file_put_contents('/tmp/debug.log', "After createTrace call\n", FILE_APPEND);
    
    return response()->json([
        'message' => 'Eloquent ORM operation with automatic tracing',
        'users_count' => $users->count(),
        'first_user' => $users->first() ? $users->first()->only(['id', 'name', 'email']) : null
    ]);
});

// Example of PDO database tracing with direct PDO connection
Route::get('/api/pdo-example', function () {
    try {
        // Create PDO connection (normally you'd use a connection pool)
        $dsn = 'mysql:host=' . env('DB_HOST', 'mysql') . ';dbname=' . env('DB_DATABASE', 'laravel');
        $pdo = new PDO($dsn, env('DB_USERNAME', 'root'), env('DB_PASSWORD', 'secret'));
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        // Example of traced PDO query using helper function
        $query = 'SELECT VERSION() as mysql_version, DATABASE() as current_db';
        
        // Use traced_pdo_query helper function for automatic tracing
        $result = traced_pdo_query($pdo, $query);
        $data = $result->fetch(PDO::FETCH_ASSOC);
        
        return response()->json([
            'message' => 'PDO database operation with tracing',
            'traced' => true,
            'data' => $data
        ]);
    } catch (Exception $e) {
        return response()->json([
            'message' => 'PDO database operation failed',
            'error' => $e->getMessage(),
            'traced' => true
        ], 500);
    }
});

// Example of PDO prepared statement tracing
Route::get('/api/pdo-prepared-example', function () {
    try {
        // Create PDO connection
        $dsn = 'mysql:host=' . env('DB_HOST', 'localhost') . ';dbname=' . env('DB_DATABASE', 'laravel');
        $pdo = new PDO($dsn, env('DB_USERNAME', 'root'), env('DB_PASSWORD', ''));
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        // Create a simple table for demonstration
        traced_pdo_query($pdo, 'CREATE TEMPORARY TABLE users_demo (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100))');
        
        // Insert some sample data using prepared statements
        $stmt = traced_pdo_prepare($pdo, 'INSERT INTO users_demo (name, email) VALUES (?, ?)');
        $stmt->execute(['John Doe', 'john@example.com']);
        $stmt->execute(['Jane Smith', 'jane@example.com']);
        
        // Query the data
        $selectStmt = traced_pdo_prepare($pdo, 'SELECT * FROM users_demo WHERE name LIKE ?');
        $selectStmt->execute(['%John%']);
        $users = $selectStmt->fetchAll(PDO::FETCH_ASSOC);
        
        return response()->json([
            'message' => 'PDO prepared statement operations with tracing',
            'traced' => true,
            'users' => $users
        ]);
    } catch (Exception $e) {
        return response()->json([
            'message' => 'PDO prepared statement operation failed',
            'error' => $e->getMessage(),
            'traced' => true
        ], 500);
    }
});

// Example of database transaction tracing
Route::get('/api/database-transaction-example', function () {
    try {
        // Create PDO connection
        $dsn = 'mysql:host=' . env('DB_HOST', 'localhost') . ';dbname=' . env('DB_DATABASE', 'laravel');
        $pdo = new PDO($dsn, env('DB_USERNAME', 'root'), env('DB_PASSWORD', ''));
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        // Start transaction
        $pdo->beginTransaction();
        
        // Create temporary table
        traced_pdo_query($pdo, 'CREATE TEMPORARY TABLE transaction_demo (id INT AUTO_INCREMENT PRIMARY KEY, amount DECIMAL(10,2))');
        
        // Insert some data within transaction
        $stmt = traced_pdo_prepare($pdo, 'INSERT INTO transaction_demo (amount) VALUES (?)');
        $stmt->execute([100.50]);
        $stmt->execute([200.75]);
        
        // Update data within transaction
        $updateStmt = traced_pdo_prepare($pdo, 'UPDATE transaction_demo SET amount = amount * 1.1 WHERE id = ?');
        $updateStmt->execute([1]);
        
        // Query the results
        $result = traced_pdo_query($pdo, 'SELECT * FROM transaction_demo ORDER BY id');
        $data = $result->fetchAll(PDO::FETCH_ASSOC);
        
        // Commit transaction
        $pdo->commit();
        
        return response()->json([
            'message' => 'Database transaction completed with tracing',
            'traced' => true,
            'data' => $data
        ]);
    } catch (Exception $e) {
        // Rollback on error
        if ($pdo->inTransaction()) {
            $pdo->rollback();
        }
        
        return response()->json([
            'message' => 'Database transaction failed',
            'error' => $e->getMessage(),
            'traced' => true
        ], 500);
    }
});

// Example of database error tracing
Route::get('/api/database-error-example', function () {
    try {
        // Create PDO connection
        $dsn = 'mysql:host=' . env('DB_HOST', 'localhost') . ';dbname=' . env('DB_DATABASE', 'laravel');
        $pdo = new PDO($dsn, env('DB_USERNAME', 'root'), env('DB_PASSWORD', ''));
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        // Intentionally cause an error for tracing demonstration
        $result = traced_pdo_query($pdo, 'SELECT * FROM nonexistent_table');
        
        return response()->json([
            'message' => 'This should not be reached',
            'traced' => true
        ]);
    } catch (Exception $e) {
        return response()->json([
            'message' => 'Database error traced successfully',
            'error' => $e->getMessage(),
            'traced' => true
        ], 500);
    }
});

Route::get('/api/slow-example', function () {
    // Example of tracing a slow operation
    $GLOBALS['simple_tracer']->createTrace('slow.operation', [
        'duration' => '1000ms'
    ]);
    
    sleep(1); // Simulate slow operation
    
    return response()->json([
        'message' => 'Slow operation completed',
        'duration' => '1 second'
    ]);
});

// Example of tracing HTTP client calls with curl
Route::get('/api/curl-example', function () {
    // Example of making an external HTTP call with curl tracing
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://jsonplaceholder.typicode.com/posts/1');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    
    // Use the traced curl execution
    $result = traced_curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    return response()->json([
        'message' => 'External API call completed with curl',
        'http_code' => $httpCode,
        'traced' => true,
        'data' => json_decode($result, true)
    ]);
});

// Example of tracing HTTP client calls with Guzzle
Route::get('/api/guzzle-example', function () {
    // Example of making an external HTTP call with Guzzle tracing
    $client = new \GuzzleHttp\Client();
    
    try {
        // Use the traced Guzzle request
        $response = traced_guzzle_request($client, 'GET', 'https://jsonplaceholder.typicode.com/posts/2');
        
        return response()->json([
            'message' => 'External API call completed with Guzzle',
            'http_code' => $response->getStatusCode(),
            'traced' => true,
            'data' => json_decode($response->getBody()->getContents(), true)
        ]);
    } catch (Exception $e) {
        return response()->json([
            'message' => 'External API call failed',
            'error' => $e->getMessage(),
            'traced' => true
        ], 500);
    }
});

// Example of multiple HTTP client calls in one request
Route::get('/api/multi-http-example', function () {
    $results = [];
    
    // Make multiple external calls with different methods
    $client = new \GuzzleHttp\Client();
    
    try {
        // GET request with Guzzle
        $response1 = traced_guzzle_request($client, 'GET', 'https://jsonplaceholder.typicode.com/users/1');
        $results['user'] = json_decode($response1->getBody()->getContents(), true);
        
        // POST request with curl
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'https://jsonplaceholder.typicode.com/posts');
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode([
            'title' => 'Test Post',
            'body' => 'This is a test post',
            'userId' => 1
        ]));
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        
        $postResult = traced_curl_exec($ch);
        $results['post'] = json_decode($postResult, true);
        curl_close($ch);
        
    } catch (Exception $e) {
        return response()->json([
            'message' => 'One or more external API calls failed',
            'error' => $e->getMessage(),
            'traced' => true
        ], 500);
    }
    
    return response()->json([
        'message' => 'Multiple external API calls completed',
        'traced' => true,
        'results' => $results
    ]);
});

// Example: Instrumented curl call to Postman random joke API
Route::get('/api/joke-curl', function () {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://official-joke-api.appspot.com/random_joke');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    $result = traced_curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    $data = json_decode($result, true);
    return response()->json([
        'message' => 'Joke fetched with curl',
        'http_code' => $httpCode,
        'joke' => $data
    ]);
});

// Example: Instrumented Guzzle call to Postman random joke API
Route::get('/api/joke-guzzle', function () {
    $client = new \GuzzleHttp\Client();
    try {
        $response = traced_guzzle_request($client, 'GET', 'https://official-joke-api.appspot.com/random_joke');
        $data = json_decode($response->getBody()->getContents(), true);
        return response()->json([
            'message' => 'Joke fetched with Guzzle',
            'http_code' => $response->getStatusCode(),
            'joke' => $data
        ]);
    } catch (Exception $e) {
        return response()->json([
            'message' => 'Failed to fetch joke with Guzzle',
            'error' => $e->getMessage()
        ], 500);
    }
});

// Eloquent ORM example for OpenTelemetry DB tracing
date_default_timezone_set('UTC');
use App\User;

Route::get('/api/eloquent-example', function () {
    // Clear debug log for this test
    file_put_contents('/tmp/debug.log', "\n--- /api/eloquent-example called at ".date('Y-m-d H:i:s')." ---\n", FILE_APPEND);
    
    // Fetch paginated users using Eloquent ORM
    $users = User::where('email', 'like', '%@%')->paginate(5);
    
    // Log result count
    file_put_contents('/tmp/debug.log', "Fetched ".count($users)." users\n", FILE_APPEND);
    
    // Return paginated users as JSON
    return response()->json([
        'message' => 'Eloquent ORM paginated users',
        'users' => $users->items(),
        'pagination' => [
            'current_page' => $users->currentPage(),
            'last_page' => $users->lastPage(),
            'total' => $users->total(),
        ]
    ]);
});
