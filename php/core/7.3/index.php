<?php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/last9/instrumentation.php';

// Use our DB class instead of PDO directly
$pdo = \Last9\DB::connect(
    "mysql:host=" . getenv('DB_HOST') . ";dbname=" . getenv('DB_NAME'),
    getenv('DB_USER'),
    getenv('DB_PASSWORD')
);

// Create table if not exists
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS dice_rolls (
        id INT AUTO_INCREMENT PRIMARY KEY,
        roll_value INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");
} catch (\Exception $e) {
    error_log("Error creating table: " . $e->getMessage());
}

// Initialize instrumented HTTP client
$http = new \Last9\InstrumentedHttpClient([
    'timeout' => 5,
    'connect_timeout' => 2,
    'verify' => false  // Added to handle HTTPS issues
]);

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

try {
    switch ($uri) {
        case '/':
            echo "Hello World!";
            break;

        case '/rolldice':
            $result = random_int(1, 6);
            
            // Insert new roll
            $stmt = $pdo->prepare("INSERTT INTO dice_rolls (roll_value) VALUES (?)");
            $stmt->execute([$result]);
            
            // Get last 5 rolls with error logging
            try {
                $stmt = $pdo->prepare("SELECT roll_value, created_at FROM dice_rolls ORDER BY created_at DESC LIMIT 5");
                $stmt->execute();
                $previousRolls = $stmt->fetchAll(\PDO::FETCH_ASSOC);
                // error_log("Previous rolls: " . print_r($previousRolls, true));
            } catch (\Exception $e) {
                error_log("Error fetching previous rolls: " . $e->getMessage());
                $previousRolls = [];
            }
            
            // Make external API call with error handling
            try {
                $response = $http->request('GET', "http://numbersapi.com/{$result}/math", [
                    'headers' => [
                        'Accept' => 'text/plain',
                        'User-Agent' => 'PHP/1.0'
                    ],
                    'verify' => false,  // Disable SSL verification for testing
                    'timeout' => 30
                ]);
                $numberFact = $response->getBody();
                error_log("Number fact API response: " . $numberFact);
            } catch (\Exception $e) {
                error_log("Error fetching number fact: " . $e->getMessage() . "\n" . $e->getTraceAsString());
                $numberFact = "Could not fetch fact due to: " . $e->getMessage();
            }
            
            $response = [
                'current_roll' => $result,
                'fact' => "test",
                'previous_rolls' => $previousRolls
            ];
            
//          error_log("Sending response: " . print_r($response, true));
            echo json_encode($response, JSON_PRETTY_PRINT);
            break;

        default:
            http_response_code(404);
            echo "404 Not Found";
            break;
    }
} catch (Exception $e) {
    error_log("Main error: " . $e->getMessage());
    http_response_code(500);
    echo "Error: " . $e->getMessage();
}