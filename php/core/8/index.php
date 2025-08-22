<?php

require __DIR__ . '/vendor/autoload.php';

// Enable exporting of traces to Last9 (as per Last9 docs)
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Common\Time\ClockFactory;
use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Instrumentation\Configurator;

// Parse headers from environment variable for Last9 authentication
$headers = [];
$otlpHeaders = getenv('OTEL_EXPORTER_OTLP_HEADERS');
if ($otlpHeaders) {
    $headerPairs = explode(',', $otlpHeaders);
    foreach ($headerPairs as $headerPair) {
        $parts = explode('=', $headerPair, 2);
        if (count($parts) === 2) {
            $headers[trim($parts[0])] = trim($parts[1]);
        }
    }
}

// Create Last9-specific transport
$transport = (new OtlpHttpTransportFactory())->create(
    getenv('OTEL_EXPORTER_OTLP_ENDPOINT'), 
    'application/json', 
    $headers
);
$exporter = new SpanExporter($transport);

$tracerProvider = new TracerProvider(
    new BatchSpanProcessor($exporter, ClockFactory::getDefault())
);

// Register TracerProvider with Globals for auto-instrumentation
Globals::registerInitializer(function (Configurator $configurator) use ($tracerProvider) {
    return $configurator->withTracerProvider($tracerProvider);
});

use \Last9\Instrumentation;

// Initialize instrumentation
$instrumentation = Instrumentation::init(getenv('OTEL_SERVICE_NAME'));

try {
   // MySQL connection (uncommented now that traces are working)
   try {
       // Create mysqli connection
       $mysqli = new mysqli(
           getenv('DB_HOST') ?: 'localhost',
           getenv('DB_USER') ?: 'root', 
           getenv('DB_PASSWORD') ?: '',
           getenv('DB_NAME') ?: 'test'
       );

       if ($mysqli->connect_errno) {
           error_log("MySQL connection failed: " . $mysqli->connect_error);
           $mysqli = null; // Set to null if connection fails
       }
   } catch (\Exception $e) {
       error_log("MySQL exception: " . $e->getMessage());
       $mysqli = null; // Set to null if connection fails
   }

   // Only create table if MySQL connection succeeded
   if ($mysqli) {
       try {
           $mysqli->query("CREATE TABLE IF NOT EXISTS dice_rolls (
               id INT AUTO_INCREMENT PRIMARY KEY,
               roll_value INT NOT NULL,
               created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
           )");
       } catch (\Exception $e) {
           error_log("Error creating table: " . $e->getMessage());
       }
   }

   // Initialize HTTP client
   $http = new \GuzzleHttp\Client([
       'timeout' => 5,
       'connect_timeout' => 2,
       'verify' => false
   ]);

   $uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

   switch ($uri) {
       case '/':
           echo "Hello World!";
           break;

       case '/rolldice':
           try {
               $result = random_int(1, 6);

               // MySQL operations (now uncommented)
               if ($mysqli) {
                   // Insert new roll
                   try {
                       $stmt = $mysqli->prepare("INSERT INTO dice_rolls (roll_value) VALUES (?)");
                       if (!$stmt) {
                           throw new Exception("Prepare failed: " . $mysqli->error);
                       }
                       $stmt->bind_param("i", $result);
                       if (!$stmt->execute()) {
                           throw new Exception("Execute failed: " . $stmt->error);
                       }
                   } catch (\Exception $e) {
                       error_log("MySQL insert error: " . $e->getMessage());
                   }

                   // Get last 5 rolls
                   try {
                       $stmt = $mysqli->prepare("SELECT roll_value, created_at FROM dice_rolls ORDER BY created_at DESC LIMIT 5");
                       if (!$stmt) {
                           throw new Exception("Prepare failed for select: " . $mysqli->error);
                       }
                       if (!$stmt->execute()) {
                           throw new Exception("Execute failed for select: " . $stmt->error);
                       }

                       $query_result = $stmt->get_result();
                       $previousRolls = [];
                       while ($row = $query_result->fetch_assoc()) {
                           $previousRolls[] = $row;
                       }
                   } catch (\Exception $e) {
                       error_log("MySQL select error: " . $e->getMessage());
                       $previousRolls = [];
                   }
               } else {
                   // Fallback to mock data if MySQL is not available
                   $previousRolls = [
                       ['roll_value' => 3, 'created_at' => date('Y-m-d H:i:s')],
                       ['roll_value' => 5, 'created_at' => date('Y-m-d H:i:s', time() - 60)],
                   ];
               }
               try {
                   $response = $http->request('GET', "http://numbersapi.com/{$result}/math", [
                       'headers' => [
                           'Accept' => 'text/plain',
                           'User-Agent' => 'PHP/1.0'
                       ],
                       'verify' => false,
                       'timeout' => 30
                   ]);
                   $numberFact = $response->getBody()->getContents();
               } catch (\Exception $e) {
                   $numberFact = "Could not fetch fact due to: " . $e->getMessage();
               }

               $response = [
                   'current_roll' => $result,
                   'fact' => $numberFact,
                   'previous_rolls' => $previousRolls
               ];

               echo json_encode($response, JSON_PRETTY_PRINT);


           } catch (\Exception $e) {
               throw $e;
           }
           $instrumentation->setSuccess();
           break;

       default:
           http_response_code(404);
           echo "404 Not Found";
           $instrumentation->setError(new Exception("404 Not Found"));
           break;
   }

} catch (Exception $e) {
   $instrumentation->setError($e);
   error_log("Main error: " . $e->getMessage());
   http_response_code(500);
   echo "Error: " . $e->getMessage();
}
