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

// Test endpoint to verify middleware performance optimizations
Route::get('/api/test-middleware-performance', function () {
    $startTime = microtime(true);
    
    // This endpoint will be traced due to /api prefix
    // Test database query to see full span creation
    $userCount = \App\User::count();
    
    $endTime = microtime(true);
    $executionTime = ($endTime - $startTime) * 1000; // Convert to milliseconds
    
    return response()->json([
        'message' => 'Middleware performance test completed',
        'optimizations' => [
            'removed_sampling_code' => 'Static variables and unused conditionalTrace method removed',
            'optimized_attributes' => 'Reduced HTTP attributes collection overhead',
            'streamlined_span_name' => 'Improved span name generation performance',
            'route_filtering' => 'Non-traced routes skip all instrumentation'
        ],
        'execution_time_ms' => round($executionTime, 2),
        'user_count' => $userCount,
        'traced' => 'This request should appear in traces with optimized attributes'
    ]);
});

// Test endpoint for non-traced route (should have minimal overhead)
Route::get('/test-non-traced-performance', function () {
    $startTime = microtime(true);
    
    // This endpoint will NOT be traced (no /api prefix)
    $userCount = \App\User::count();
    
    $endTime = microtime(true);
    $executionTime = ($endTime - $startTime) * 1000; // Convert to milliseconds
    
    return response()->json([
        'message' => 'Non-traced route performance test',
        'execution_time_ms' => round($executionTime, 2),
        'user_count' => $userCount,
        'traced' => 'This request should NOT appear in traces (minimal middleware overhead)'
    ]);
});

// ===== NEW TEST ROUTES FOR URL FOLDING AND TRACING =====

// Test route with parameter - should fold to /api/users/{id}
Route::get('/api/users/{id}', function ($id) {
    $user = \App\User::find($id);
    
    if (!$user) {
        return response()->json(['error' => 'User not found'], 404);
    }
    
    return response()->json([
        'message' => 'User details retrieved',
        'user' => [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email
        ],
        'route_info' => 'This should fold to GET /api/users/{id} in traces',
        'actual_id' => $id
    ]);
})->name('api.users.show');

// Test route with multiple parameters - should fold to /api/users/{user}/posts/{post}
Route::get('/api/users/{user}/posts/{post}', function ($userId, $postId) {
    return response()->json([
        'message' => 'User post details',
        'user_id' => $userId,
        'post_id' => $postId,
        'route_info' => 'This should fold to GET /api/users/{user}/posts/{post} in traces'
    ]);
})->name('api.users.posts.show');

// Test POST route - should fold to POST /api/users
Route::post('/api/users', function () {
    return response()->json([
        'message' => 'User creation endpoint',
        'method' => 'POST',
        'route_info' => 'This should fold to POST /api/users in traces'
    ]);
});

// Test PUT route - should fold to PUT /api/users/{id}
Route::put('/api/users/{id}', function ($id) {
    return response()->json([
        'message' => 'User update endpoint',
        'method' => 'PUT',
        'user_id' => $id,
        'route_info' => 'This should fold to PUT /api/users/{id} in traces'
    ]);
});

// Test DELETE route - should fold to DELETE /api/users/{id}
Route::delete('/api/users/{id}', function ($id) {
    return response()->json([
        'message' => 'User deletion endpoint',
        'method' => 'DELETE',
        'user_id' => $id,
        'route_info' => 'This should fold to DELETE /api/users/{id} in traces'
    ]);
});

// Test route with UUID parameter - should fold to /api/orders/{uuid}
Route::get('/api/orders/{uuid}', function ($uuid) {
    return response()->json([
        'message' => 'Order details',
        'uuid' => $uuid,
        'route_info' => 'This should fold to GET /api/orders/{uuid} in traces (UUID pattern)'
    ]);
});

// Test route with date parameter - should fold to /api/analytics/{date}
Route::get('/api/analytics/{date}', function ($date) {
    return response()->json([
        'message' => 'Analytics for date',
        'date' => $date,
        'route_info' => 'This should fold to GET /api/analytics/{date} in traces (date pattern)'
    ]);
});

// Test route with search query - should fold to /api/search/{query}
Route::get('/api/search/{query}', function ($query) {
    return response()->json([
        'message' => 'Search results',
        'query' => $query,
        'route_info' => 'This should fold to GET /api/search/{query} in traces (search pattern)'
    ]);
});

// Test route with pagination - should fold to /api/articles/{page}/{per_page}
Route::get('/api/articles/{page}/{per_page}', function ($page, $perPage) {
    return response()->json([
        'message' => 'Paginated articles',
        'page' => $page,
        'per_page' => $perPage,
        'route_info' => 'This should fold to GET /api/articles/{page}/{per_page} in traces (pagination pattern)'
    ]);
});

// Test route generation with tracing
Route::get('/api/test-route-generation', function () {
    try {
        // Test route generation with tracing
        $userRoute = traced_laravel_route('api.users.show', ['id' => 123]);
        $postRoute = traced_laravel_route('api.users.posts.show', ['user' => 123, 'post' => 456]);
        
        return response()->json([
            'message' => 'Route generation test completed',
            'generated_routes' => [
                'user_route' => $userRoute,
                'post_route' => $postRoute
            ],
            'route_names' => [
                'user_route_name' => 'api.users.show',
                'post_route_name' => 'api.users.posts.show'
            ],
            'traced' => 'Route generation spans should appear in traces'
        ]);
        
    } catch (Exception $e) {
        return response()->json([
            'message' => 'Route generation test failed',
            'error' => $e->getMessage(),
            'note' => 'Make sure route names are defined in your routes file'
        ], 500);
    }
});

// Test URL folding with different patterns
Route::get('/api/test-url-folding', function () {
    $testUrls = [
        'GET' => [
            'https://example.com/api/users/123' => 'Should fold to GET /api/users/{id}',
            'https://example.com/api/users/456/posts/789' => 'Should fold to GET /api/users/{id}/posts/{id}',
            'https://example.com/api/orders/550e8400-e29b-41d4-a716-446655440000' => 'Should fold to GET /api/orders/{uuid}',
            'https://example.com/api/analytics/2024-01-15' => 'Should fold to GET /api/analytics/{date}',
            'https://example.com/api/search/laravel+tutorial' => 'Should fold to GET /api/search/{query}',
            'https://example.com/api/articles/2/10' => 'Should fold to GET /api/articles/{page}/{per_page}'
        ],
        'POST' => [
            'https://example.com/api/users' => 'Should fold to POST /api/users'
        ],
        'PUT' => [
            'https://example.com/api/users/123' => 'Should fold to PUT /api/users/{id}'
        ],
        'DELETE' => [
            'https://example.com/api/users/123' => 'Should fold to DELETE /api/users/{id}'
        ]
    ];
    
    $foldedResults = [];
    
    foreach ($testUrls as $method => $urls) {
        foreach ($urls as $url => $description) {
            $folded = fold_url($url, $method);
            $foldedResults[] = [
                'original_url' => $url,
                'method' => $method,
                'folded_url' => $folded,
                'description' => $description
            ];
        }
    }
    
    return response()->json([
        'message' => 'URL folding test completed',
        'test_results' => $foldedResults,
        'note' => 'Check traces to see how these URLs are folded for better grouping'
    ]);
});

// Test route with query parameters - should fold to /api/filter/{criteria}
Route::get('/api/filter/{criteria}', function ($criteria) {
    $query = request()->query();
    
    return response()->json([
        'message' => 'Filter results',
        'criteria' => $criteria,
        'query_params' => $query,
        'route_info' => 'This should fold to GET /api/filter/{criteria} in traces (query params removed)'
    ]);
});

// Test route with action suffix - should fold to /api/users/{id}/{action}
Route::get('/api/users/{id}/edit', function ($id) {
    return response()->json([
        'message' => 'Edit user form',
        'user_id' => $id,
        'action' => 'edit',
        'route_info' => 'This should fold to GET /api/users/{id}/{action} in traces (action pattern)'
    ]);
});

Route::get('/api/users/{id}/show', function ($id) {
    return response()->json([
        'message' => 'Show user details',
        'user_id' => $id,
        'action' => 'show',
        'route_info' => 'This should fold to GET /api/users/{id}/{action} in traces (action pattern)'
    ]);
});

// Test route with nested resources - should fold to /api/categories/{category}/products/{product}/reviews/{review}
Route::get('/api/categories/{category}/products/{product}/reviews/{review}', function ($categoryId, $productId, $reviewId) {
    return response()->json([
        'message' => 'Nested resource details',
        'category_id' => $categoryId,
        'product_id' => $productId,
        'review_id' => $reviewId,
        'route_info' => 'This should fold to GET /api/categories/{category}/products/{product}/reviews/{review} in traces'
    ]);
});

// Test route with numeric ID and text - should fold to /api/posts/{id}/{slug}
Route::get('/api/posts/{id}/{slug}', function ($id, $slug) {
    return response()->json([
        'message' => 'Post details by ID and slug',
        'post_id' => $id,
        'slug' => $slug,
        'route_info' => 'This should fold to GET /api/posts/{id}/{slug} in traces (mixed parameter types)'
    ]);
});

// Test route with year/month pattern - should fold to /api/archive/{year}/{month}
Route::get('/api/archive/{year}/{month}', function ($year, $month) {
    return response()->json([
        'message' => 'Archive for year/month',
        'year' => $year,
        'month' => $month,
        'route_info' => 'This should fold to GET /api/archive/{year}/{month} in traces (date pattern)'
    ]);
});

// Test route with multiple numeric IDs - should fold to /api/comparison/{id1}/{id2}
Route::get('/api/comparison/{id1}/{id2}', function ($id1, $id2) {
    return response()->json([
        'message' => 'Comparison between two items',
        'id1' => $id1,
        'id2' => $id2,
        'route_info' => 'This should fold to GET /api/comparison/{id1}/{id2} in traces (multiple numeric IDs)'
    ]);
});

// Test route with mixed parameter types - should fold to /api/mixed/{type}/{id}/{action}
Route::get('/api/mixed/{type}/{id}/{action}', function ($type, $id, $action) {
    return response()->json([
        'message' => 'Mixed parameter types test',
        'type' => $type,
        'id' => $id,
        'action' => $action,
        'route_info' => 'This should fold to GET /api/mixed/{type}/{id}/{action} in traces (mixed types)'
    ]);
});

// Include Redis and Queue test routes
require __DIR__ . '/redis_queue.php';