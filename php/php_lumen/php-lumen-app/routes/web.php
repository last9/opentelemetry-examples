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
    
    // Controller-based error endpoints
    $router->get('/division-by-zero', 'TestController@divisionByZero');
    $router->get('/undefined-variable', 'TestController@undefinedVariable');
    $router->get('/array-access-error', 'TestController@arrayAccessError');
    $router->get('/file-not-found', 'TestController@fileNotFound');
    $router->get('/database-connection-error', 'TestController@databaseConnectionError');
    $router->get('/custom-exception', 'TestController@customException');
    $router->get('/json-decode-error', 'TestController@jsonDecodeError');
    $router->get('/http-client-error', 'TestController@httpClientError');
    $router->get('/multiple-errors', 'TestController@multipleErrors');
});

// Error and Exception Testing Routes
$router->group(['prefix' => 'errors'], function () use ($router) {
    // Division by zero error
    $router->get('/division-by-zero', function () {
        $result = 10 / 0;
        return ['result' => $result];
    });
    
    // Undefined variable error
    $router->get('/undefined-variable', function () {
        return ['undefined_var' => $undefinedVariable];
    });
    
    // Array access error
    $router->get('/array-access', function () {
        $array = [1, 2, 3];
        return ['value' => $array[10]];
    });
    
    // File not found error
    $router->get('/file-not-found', function () {
        $content = file_get_contents('/non/existent/file.txt');
        return ['content' => $content];
    });
    
    // Database connection error (simulated)
    $router->get('/database-error', function () {
        throw new \Exception('Database connection failed: Connection refused');
    });
    
    // Custom exception
    $router->get('/custom-exception', function () {
        throw new \InvalidArgumentException('This is a custom invalid argument exception');
    });
    
    // Memory limit error (simulated)
    $router->get('/memory-error', function () {
        $largeArray = [];
        for ($i = 0; $i < 1000000000; $i++) {
            $largeArray[] = str_repeat('x', 1000);
        }
        return ['memory_used' => memory_get_usage()];
    });
    
    // Timeout error (simulated)
    $router->get('/timeout-error', function () {
        sleep(30); // This will timeout
        return ['status' => 'completed'];
    });
    
    // JSON decode error
    $router->get('/json-error', function () {
        $invalidJson = '{"invalid": json}';
        $data = json_decode($invalidJson, true);
        return ['data' => $data];
    });
    
    // HTTP client error (simulated)
    $router->get('/http-error', function () {
        $client = new \GuzzleHttp\Client();
        $response = $client->get('http://invalid-domain-that-does-not-exist-12345.com');
        return ['response' => $response->getBody()];
    });
    
    // Multiple errors in sequence
    $router->get('/multiple-errors', function () {
        $errors = [];
        
        try {
            $result = 10 / 0;
        } catch (\Exception $e) {
            $errors[] = 'Division by zero: ' . $e->getMessage();
        }
        
        try {
            $undefinedVar;
        } catch (\Exception $e) {
            $errors[] = 'Undefined variable: ' . $e->getMessage();
        }
        
        try {
            $array = [1, 2, 3];
            $array[10];
        } catch (\Exception $e) {
            $errors[] = 'Array access: ' . $e->getMessage();
        }
        
        return ['errors' => $errors];
    });
});
