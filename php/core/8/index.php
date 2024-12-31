<?php
require __DIR__ . '/vendor/autoload.php';
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Common\Time\ClockFactory;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\Context\Context;

// Your existing OTLP setup
$transport = (new OtlpHttpTransportFactory())->create(getenv('OTEL_EXPORTER_OTLP_ENDPOINT'), 'application/x-protobuf');
$exporter = new SpanExporter($transport);
$tracerProvider = new TracerProvider(
   new BatchSpanProcessor($exporter, ClockFactory::getDefault())
);

// Get tracer and create root span
$tracer = $tracerProvider->getTracer('dice-app');
$rootSpan = $tracer->spanBuilder($_SERVER['REQUEST_URI'])
   ->setSpanKind(SpanKind::KIND_SERVER)
   ->startSpan();

// Create and attach context
$rootContext = Context::getCurrent()->withContextValue($rootSpan);
$scope = $rootContext->activate();

// Set HTTP attributes
$rootSpan->setAttributes([
   'http.method' => $_SERVER['REQUEST_METHOD'],
   'http.target' => $_SERVER['REQUEST_URI'],
   'http.host' => $_SERVER['HTTP_HOST'] ?? 'unknown',
   'http.scheme' => isset($_SERVER['HTTPS']) ? 'https' : 'http',
]);

try {
   // Create mysqli connection
   $mysqli = new mysqli(
       getenv('DB_HOST'),
       getenv('DB_USER'),
       getenv('DB_PASSWORD'),
       getenv('DB_NAME')
   );

   // Check connection
   if ($mysqli->connect_errno) {
       error_log("Failed to connect to MySQL: " . $mysqli->connect_error);
       exit("Database connection failed");
   }

   // Create table if not exists
   try {
       $mysqli->query("CREATE TABLE IF NOT EXISTS dice_rolls (
           id INT AUTO_INCREMENT PRIMARY KEY,
           roll_value INT NOT NULL,
           created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
       )");
   } catch (\Exception $e) {
       error_log("Error creating table: " . $e->getMessage());
   }

   // Initialize instrumented HTTP client
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
           // Create child span without explicitly setting parent
           $rollSpan = $tracer->spanBuilder('roll-dice')
               ->setSpanKind(SpanKind::KIND_INTERNAL)
               ->startSpan();
           $rollScope = Context::getCurrent()->withContextValue($rollSpan)->activate();

           try {
               $result = random_int(1, 6);

               // Insert new roll
               $stmt = $mysqli->prepare("INSERT INTO dice_rolls (roll_value) VALUES (?)");
               if (!$stmt) {
                   throw new Exception("Prepare failed: " . $mysqli->error);
               }
               $stmt->bind_param("i", $result);
               if (!$stmt->execute()) {
                   throw new Exception("Execute failed: " . $stmt->error);
               }

               // Get last 5 rolls
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

               // Make external API call with error handling
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
                   error_log("Number fact API response: " . $numberFact);
               } catch (\Exception $e) {
                   error_log("Error fetching number fact: " . $e->getMessage() . "\n" . $e->getTraceAsString());
                   $numberFact = "Could not fetch fact due to: " . $e->getMessage();
               }

               $response = [
                   'current_roll' => $result,
                   'fact' => $numberFact,
                   'previous_rolls' => $previousRolls
               ];

               echo json_encode($response, JSON_PRETTY_PRINT);

           } catch (\Exception $e) {
               $rollSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
               throw $e;
           } finally {
               $rollScope->detach();
               $rollSpan->end();
           }
           break;

       default:
           http_response_code(404);
           echo "404 Not Found";
           break;
   }
} catch (Exception $e) {
   $rootSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
   error_log("Main error: " . $e->getMessage());
   http_response_code(500);
   echo "Error: " . $e->getMessage();
} finally {
   $scope->detach();
   $rootSpan->end();
}
