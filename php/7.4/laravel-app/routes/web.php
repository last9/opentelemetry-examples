<?php

use Illuminate\Support\Facades\Route;
use App\User;

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
    return view('welcome');
});

// Health check endpoint - basic functionality test
Route::get('/api/health', function () {
    return response()->json([
        'status' => 'healthy',
        'service' => 'laravel-otel-app',
        'timestamp' => date('Y-m-d H:i:s')
    ]);
});

// Main example endpoint - demonstrates database tracing via AppServiceProvider
Route::get('/api/eloquent-example', function () {
    // This endpoint will automatically generate database spans via AppServiceProvider::boot()
    // The DB::listen() callback will create spans for both the count and select queries
    
    // Count total users (will generate a database span)
    $totalUsers = User::count();
    
    // Fetch specific user by ID (will generate database span with parameter binding)
    $specificUser = User::find(1);
    
    // Fetch paginated users using Eloquent ORM (will generate database spans)
    $users = User::where('email', 'like', '%@%')->paginate(5);
    
    // Return paginated users as JSON
    return response()->json([
        'message' => 'Eloquent ORM paginated users',
        'total_users' => $totalUsers,
        'specific_user' => $specificUser ? [
            'id' => $specificUser->id,
            'name' => $specificUser->name,
            'email' => $specificUser->email
        ] : null,
        'users' => $users->items(),
        'pagination' => [
            'current_page' => $users->currentPage(),
            'last_page' => $users->lastPage(),
            'total' => $users->total(),
        ]
    ]);
});

// Test cURL external HTTP calls with tracing
Route::get('/api/test-curl', function () {
    try {
        // Initialize cURL
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'https://httpbin.org/get?source=laravel-otel');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Laravel-OpenTelemetry-Test/1.0');
        
        // Use traced cURL execution (will create HTTP client span)
        $result = traced_curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        return response()->json([
            'message' => 'cURL external call completed',
            'http_code' => $httpCode,
            'success' => $httpCode >= 200 && $httpCode < 300,
            'response_preview' => substr($result, 0, 200) . '...',
            'traced' => 'HTTP client span should appear in traces'
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'message' => 'cURL external call failed',
            'error' => $e->getMessage(),
            'traced' => 'Error span should appear in traces'
        ], 500);
    }
});

// Test Guzzle external HTTP calls with tracing  
Route::get('/api/test-guzzle', function () {
    try {
        // Check if Guzzle is available
        if (!class_exists('GuzzleHttp\Client')) {
            return response()->json([
                'message' => 'Guzzle HTTP client not available',
                'note' => 'Install with: composer require guzzlehttp/guzzle',
                'alternative' => 'Use /api/test-curl endpoint instead'
            ], 501);
        }
        
        $client = new \GuzzleHttp\Client();
        
        // Use traced Guzzle request (will create HTTP client span)
        $response = traced_guzzle_request($client, 'GET', 'https://httpbin.org/get', [
            'query' => ['source' => 'laravel-otel-guzzle'],
            'headers' => ['User-Agent' => 'Laravel-OpenTelemetry-Test/1.0'],
            'timeout' => 10
        ]);
        
        $statusCode = $response->getStatusCode();
        $body = $response->getBody()->getContents();
        
        return response()->json([
            'message' => 'Guzzle external call completed',
            'http_code' => $statusCode,
            'success' => $statusCode >= 200 && $statusCode < 300,
            'response_preview' => substr($body, 0, 200) . '...',
            'traced' => 'HTTP client span should appear in traces'
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'message' => 'Guzzle external call failed',
            'error' => $e->getMessage(),
            'traced' => 'Error span should appear in traces'
        ], 500);
    }
});

// Test PDO database calls with tracing
Route::get('/api/test-pdo', function () {
    try {
        // Get Laravel's database configuration
        $defaultConnection = config('database.default');
        $dbConfig = config("database.connections.{$defaultConnection}");
        
        if (!$dbConfig) {
            return response()->json([
                'message' => 'Database configuration not found',
                'connection' => $defaultConnection
            ], 500);
        }
        
        // Create PDO connection using Laravel's config
        $dsn = "{$dbConfig['driver']}:host={$dbConfig['host']};port={$dbConfig['port']};dbname={$dbConfig['database']}";
        $pdo = new PDO($dsn, $dbConfig['username'], $dbConfig['password'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        
        // Test 1: Simple SELECT query using traced PDO
        $stmt1 = traced_pdo_query($pdo, "SELECT COUNT(*) as user_count FROM users");
        $userCount = $stmt1->fetch()['user_count'];
        
        // Test 2: Parameterized query using traced PDO
        $stmt2 = traced_pdo_query($pdo, "SELECT id, name, email FROM users WHERE id >= ? LIMIT 3", [1]);
        $users = $stmt2->fetchAll();
        
        return response()->json([
            'message' => 'PDO database calls completed',
            'total_users' => $userCount,
            'sample_users' => $users,
            'traced' => 'Database spans should appear in traces (separate from Eloquent)',
            'connection' => [
                'driver' => $dbConfig['driver'],
                'host' => $dbConfig['host'],
                'database' => $dbConfig['database']
            ]
        ]);
        
    } catch (PDOException $e) {
        return response()->json([
            'message' => 'PDO database call failed',
            'error' => $e->getMessage(),
            'traced' => 'Error span should appear in traces'
        ], 500);
    } catch (Exception $e) {
        return response()->json([
            'message' => 'PDO test failed',
            'error' => $e->getMessage(),
            'traced' => 'Error span should appear in traces'
        ], 500);
    }
});

// Test joke fetching with cURL tracing
Route::get('/api/joke-curl', function () {
    try {
        // Initialize cURL to fetch a random joke
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'https://official-joke-api.appspot.com/random_joke');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Laravel-OpenTelemetry-Joke-Bot/1.0');
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Accept: application/json',
            'Content-Type: application/json'
        ]);
        
        // Use traced cURL execution (will create HTTP client span)
        $result = traced_curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode >= 200 && $httpCode < 300) {
            $joke = json_decode($result, true);
            return response()->json([
                'message' => 'Joke fetched successfully with cURL',
                'joke' => [
                    'setup' => $joke['setup'] ?? 'No setup',
                    'punchline' => $joke['punchline'] ?? 'No punchline',
                    'type' => $joke['type'] ?? 'unknown'
                ],
                'http_code' => $httpCode,
                'traced' => 'HTTP client span should appear in traces'
            ]);
        } else {
            return response()->json([
                'message' => 'Failed to fetch joke',
                'http_code' => $httpCode,
                'traced' => 'Error span should appear in traces'
            ], 500);
        }
        
    } catch (Exception $e) {
        return response()->json([
            'message' => 'cURL joke fetch failed',
            'error' => $e->getMessage(),
            'traced' => 'Error span should appear in traces'
        ], 500);
    }
});

// Test joke fetching with Guzzle tracing
Route::get('/api/joke-guzzle', function () {
    try {
        // Check if Guzzle is available
        if (!class_exists('GuzzleHttp\Client')) {
            return response()->json([
                'message' => 'Guzzle HTTP client not available',
                'note' => 'Install with: composer require guzzlehttp/guzzle',
                'alternative' => 'Use /api/joke-curl endpoint instead'
            ], 501);
        }
        
        $client = new \GuzzleHttp\Client();
        
        // Use traced Guzzle request to fetch a random joke
        $response = traced_guzzle_request($client, 'GET', 'https://official-joke-api.appspot.com/random_joke', [
            'headers' => [
                'User-Agent' => 'Laravel-OpenTelemetry-Joke-Bot/1.0',
                'Accept' => 'application/json',
                'Content-Type' => 'application/json'
            ],
            'timeout' => 10
        ]);
        
        $statusCode = $response->getStatusCode();
        
        if ($statusCode >= 200 && $statusCode < 300) {
            $joke = json_decode($response->getBody()->getContents(), true);
            return response()->json([
                'message' => 'Joke fetched successfully with Guzzle',
                'joke' => [
                    'setup' => $joke['setup'] ?? 'No setup',
                    'punchline' => $joke['punchline'] ?? 'No punchline',
                    'type' => $joke['type'] ?? 'unknown'
                ],
                'http_code' => $statusCode,
                'traced' => 'HTTP client span should appear in traces'
            ]);
        } else {
            return response()->json([
                'message' => 'Failed to fetch joke',
                'http_code' => $statusCode,
                'traced' => 'Error span should appear in traces'
            ], 500);
        }
        
    } catch (Exception $e) {
        return response()->json([
            'message' => 'Guzzle joke fetch failed',
            'error' => $e->getMessage(),
            'traced' => 'Error span should appear in traces'
        ], 500);
    }
});

// Test endpoint to verify route filtering configuration
Route::get('/test-tracing-config', function () {
    $config = config('otel.traced_routes');
    
    return response()->json([
        'message' => 'OpenTelemetry Route Filtering Configuration',
        'traced_routes' => $config,
        'note' => 'This endpoint itself should NOT be traced (not in /api)',
        'test_urls' => [
            '/api/health' => 'Should be traced',
            '/api/users' => 'Should be traced', 
            '/test-tracing-config' => 'Should NOT be traced',
            '/' => 'Should NOT be traced'
        ],
        'config_file' => 'config/otel.php'
    ]);
});

// Test endpoint to verify SQL parameter binding in traces
Route::get('/api/test-sql-bindings', function () {
    try {
        // Test 1: Simple parameterized query with Eloquent
        $users = \App\User::where('id', '>=', 1)
                         ->where('email', 'like', '%@%')
                         ->limit(3)
                         ->get();
        
        // Test 2: Raw query with bindings
        $userCount = \Illuminate\Support\Facades\DB::select(
            'SELECT COUNT(*) as count FROM users WHERE id > ? AND email LIKE ?', 
            [0, '%@%']
        );
        
        // Test 3: Query Builder with multiple bindings
        $recentUsers = \Illuminate\Support\Facades\DB::table('users')
            ->where('id', '>', 1)
            ->where('email', '!=', 'test@example.com')
            ->whereIn('id', [1, 2, 3, 4, 5])
            ->select('id', 'name', 'email')
            ->take(2)
            ->get();
        
        return response()->json([
            'message' => 'SQL parameter binding test completed',
            'note' => 'Check traces for db.statement.parameters attributes',
            'results' => [
                'eloquent_users' => $users->count(),
                'raw_query_count' => $userCount[0]->count ?? 0,
                'query_builder_users' => $recentUsers->count()
            ],
            'traced_queries' => [
                'eloquent_where_clause' => 'Should have bindings: [1, "%@%"]',
                'raw_select_query' => 'Should have bindings: [0, "%@%"]', 
                'query_builder' => 'Should have bindings: [1, "test@example.com", 1, 2, 3, 4, 5]'
            ]
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'message' => 'SQL parameter binding test failed',
            'error' => $e->getMessage(),
            'traced' => 'Error span should appear in traces'
        ], 500);
    }
});