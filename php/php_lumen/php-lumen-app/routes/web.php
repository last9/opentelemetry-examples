<?php

use Carbon\Carbon;

/** @var \Laravel\Lumen\Routing\Router $router */

/*
|--------------------------------------------------------------------------
| Application Routes
|--------------------------------------------------------------------------
|
| Here is where you can register all of the routes for an application.
| It is a breeze. Simply tell Lumen the URIs it should respond to
| and give it the Closure to call when that URI is requested.
|
*/

$router->get('/', function () use ($router) {
    return [
        'message' => 'Welcome to Lumen Test App',
        'version' => $router->app->version(),
        'php_version' => PHP_VERSION,
        'timestamp' => Carbon::now()->toISOString()
    ];
});

// Basic test routes
$router->get('/test', function () {
    return [
        'status' => 'success',
        'message' => 'Test endpoint working!',
        'data' => [
            'random_number' => rand(1, 100),
            'current_time' => Carbon::now()->format('Y-m-d H:i:s')
        ]
    ];
});

$router->get('/health', function () {
    return [
        'status' => 'healthy',
        'service' => 'Lumen Test App',
        'uptime' => 'running',
        'timestamp' => Carbon::now()->toISOString()
    ];
});

$router->post('/echo', function (Illuminate\Http\Request $request) {
    return [
        'message' => 'Echo endpoint',
        'received_data' => $request->all(),
        'headers' => $request->headers->all(),
        'method' => $request->method(),
        'url' => $request->url()
    ];
});

$router->get('/users', function () {
    return [
        'users' => [
            [
                'id' => 1,
                'name' => 'John Doe',
                'email' => 'john@example.com',
                'created_at' => Carbon::now()->subDays(5)->toISOString()
            ],
            [
                'id' => 2,
                'name' => 'Jane Smith',
                'email' => 'jane@example.com',
                'created_at' => Carbon::now()->subDays(3)->toISOString()
            ],
            [
                'id' => 3,
                'name' => 'Bob Johnson',
                'email' => 'bob@example.com',
                'created_at' => Carbon::now()->subDays(1)->toISOString()
            ]
        ],
        'total' => 3,
        'page' => 1
    ];
});

$router->get('/users/{id}', function ($id) {
    $users = [
        1 => ['id' => 1, 'name' => 'John Doe', 'email' => 'john@example.com'],
        2 => ['id' => 2, 'name' => 'Jane Smith', 'email' => 'jane@example.com'],
        3 => ['id' => 3, 'name' => 'Bob Johnson', 'email' => 'bob@example.com']
    ];
    
    if (!isset($users[$id])) {
        return response()->json(['error' => 'User not found'], 404);
    }
    
    return $users[$id];
});

// Controller-based routes
$router->group(['prefix' => 'api'], function () use ($router) {
    $router->get('/info', 'TestController@info');
    $router->post('/validate', 'TestController@validateRequest');
    $router->get('/error', 'TestController@error');
    $router->post('/upload', 'TestController@upload');
    $router->get('/paginated', 'TestController@paginated');
    $router->get('/cache', 'TestController@cache');
    $router->get('/trace-test', 'TestController@traceTest');
    
    // Enhanced tracing endpoints
    $router->get('/external-api-test', 'TestController@externalApiTest');
    $router->get('/database-test', 'TestController@databaseTest');
    $router->get('/cache-test', 'TestController@cacheTest');
});
