<?php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/instrumentation.php';

// Initialize database tables if needed
try {
    $createTableResult = instrumentDBQuery("
        CREATE TABLE IF NOT EXISTS dice_rolls (
            id INT AUTO_INCREMENT PRIMARY KEY,
            roll_value INT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ");
} catch (Exception $e) {
    error_log("Failed to create table: " . $e->getMessage());
}

// Simple router
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];
$operationName = $method . ' ' . $uri;

// Create root span for the request
$rootSpan = instrumentHTTPRequest($operationName);

try {
    switch ($uri) {
        case '/':
            echo "Hello World!";
            endSpan($rootSpan);
            break;

        case '/rolldice':
            // Roll the dice
            $result = random_int(1, 6);
            
            // Save to database
            $dbResult = instrumentDBQuery(
                "INSERT INTO dice_rolls (roll_value) VALUES (?)",
                [$result],
                $rootSpan['span']['spanId']
            );
            
            // Make an external API call
            $apiResult = instrumentHTTPClient(
                'GET',
                "http://numbersapi.com/{$result}/math",
                [],
                $rootSpan['span']['spanId']
            );
            
            // Get the number fact from the response
            $numberFact = $apiResult['success'] 
                ? $apiResult['response']->getBody()->getContents() 
                : "No fact available";
            
            // End the root span with success
            endSpan($rootSpan, ['code' => 1], [
                ['key' => 'dice.value', 'value' => ['intValue' => $result]]
            ]);
            
            echo json_encode([
                'roll' => $result,
                'fact' => $numberFact
            ]);
            break;

        default:
            http_response_code(404);
            endSpan($rootSpan, ['code' => 2, 'message' => 'Not Found']);
            echo "404 Not Found";
            break;
    }
} catch (Exception $e) {
    http_response_code(500);
    endSpan($rootSpan, 
        ['code' => 2, 'message' => $e->getMessage()],
        [['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]]]
    );
    echo "Error: " . $e->getMessage();
}

// Send all collected spans at the end of the request
sendTraces();