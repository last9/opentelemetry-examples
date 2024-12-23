<?php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/instrumentation.php';

// Simple router
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// Get HTTP method and create operation name
$method = $_SERVER['REQUEST_METHOD'];
$operationName = $method . ' ' . $uri;

// Route handling
switch ($uri) {
    case '/':
        echo "Hello World!";
        // Instrument the HTTP request with path-based operation name
        instrumentHTTPRequest($operationName, []);
        break;

    case '/rolldice':
        $result = random_int(1, 6);
        
        // Instrument the HTTP request with path-based operation name
        instrumentHTTPRequest($operationName, ['result' => strval($result)]);
        
        echo "Rolled dice result: $result";
        break;

    default:
        header("HTTP/1.0 404 Not Found");
        instrumentHTTPRequest($operationName, ['result' => strval($result)]);
        echo "404 Not Found";
        break;
}