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
use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Instrumentation\Configurator;

// Your existing OTLP setup
$transport = (new OtlpHttpTransportFactory())->create(getenv('OTEL_EXPORTER_OTLP_ENDPOINT'), 'application/json');
$exporter = new SpanExporter($transport);
$tracerProvider = new TracerProvider(
   new BatchSpanProcessor($exporter, ClockFactory::getDefault())
);

// Register the TracerProvider with Globals
Globals::registerInitializer(function (Configurator $configurator) use ($tracerProvider) {
    return $configurator->withTracerProvider($tracerProvider);
});

// Now get the tracer from Globals
$tracer = Globals::tracerProvider()->getTracer('dice-app');
$rootSpan = $tracer->spanBuilder('http.request')
   ->setSpanKind(SpanKind::KIND_SERVER)
   ->startSpan();

// Create root context and activate it
$ctx = Context::getCurrent()->withContextValue($rootSpan);
$scope = $ctx->activate();

try {
   // Database connection span
   $dbSpan = $tracer->spanBuilder('mysql.connect')
       ->setSpanKind(SpanKind::KIND_CLIENT)
       ->startSpan();

   $dbSpan->setAttributes([
       'db.system' => 'mysql',
       'db.user' => getenv('DB_USER'),
       'db.name' => getenv('DB_NAME'),
       'net.peer.name' => getenv('DB_HOST')
   ]);

   try {
       // Create mysqli connection
       $mysqli = new mysqli(
           getenv('DB_HOST'),
           getenv('DB_USER'),
           getenv('DB_PASSWORD'),
           getenv('DB_NAME')
       );

       if ($mysqli->connect_errno) {
           throw new Exception("Failed to connect to MySQL: " . $mysqli->connect_error);
       }
       $dbSpan->setStatus(StatusCode::STATUS_OK);
   } catch (\Exception $e) {
       $dbSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
       throw $e;
   } finally {
       $dbSpan->end();
   }

   // Create table if not exists
   $tableSpan = $tracer->spanBuilder('mysql.create_table')
       ->setSpanKind(SpanKind::KIND_CLIENT)
       ->startSpan();

   try {
       $mysqli->query("CREATE TABLE IF NOT EXISTS dice_rolls (
           id INT AUTO_INCREMENT PRIMARY KEY,
           roll_value INT NOT NULL,
           created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
       )");
       $tableSpan->setStatus(StatusCode::STATUS_OK);
   } catch (\Exception $e) {
       $tableSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
       error_log("Error creating table: " . $e->getMessage());
   } finally {
       $tableSpan->end();
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
           $rollSpan = $tracer->spanBuilder('dice.roll')
               ->setSpanKind(SpanKind::KIND_INTERNAL)
               ->startSpan();

           $rollCtx = Context::getCurrent()->withContextValue($rollSpan);
           $rollScope = $rollCtx->activate();

           try {
               $result = random_int(1, 6);

               // Insert new roll
               $insertSpan = $tracer->spanBuilder('mysql.insert')
                   ->setSpanKind(SpanKind::KIND_CLIENT)
                   ->startSpan();

               try {
                   $stmt = $mysqli->prepare("INSERT INTO dice_rolls (roll_value) VALUES (?)");
                   if (!$stmt) {
                       throw new Exception("Prepare failed: " . $mysqli->error);
                   }
                   $stmt->bind_param("i", $result);
                   if (!$stmt->execute()) {
                       throw new Exception("Execute failed: " . $stmt->error);
                   }
                   $insertSpan->setStatus(StatusCode::STATUS_OK);
               } catch (\Exception $e) {
                   $insertSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
                   throw $e;
               } finally {
                   $insertSpan->end();
               }

               // Get last 5 rolls
               $selectSpan = $tracer->spanBuilder('mysql.select')
                   ->setSpanKind(SpanKind::KIND_CLIENT)
                   ->startSpan();

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
                   $selectSpan->setStatus(StatusCode::STATUS_OK);
               } catch (\Exception $e) {
                   $selectSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
                   $previousRolls = [];
               } finally {
                   $selectSpan->end();
               }

               // Make external API call
               $apiSpan = $tracer->spanBuilder('http.numbersapi')
                   ->setSpanKind(SpanKind::KIND_CLIENT)
                   ->startSpan();

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
                   $apiSpan->setStatus(StatusCode::STATUS_OK);
               } catch (\Exception $e) {
                   $apiSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
                   $numberFact = "Could not fetch fact due to: " . $e->getMessage();
               } finally {
                   $apiSpan->end();
               }

               $response = [
                   'current_roll' => $result,
                   'fact' => $numberFact,
                   'previous_rolls' => $previousRolls
               ];

               echo json_encode($response, JSON_PRETTY_PRINT);
               $rollSpan->setStatus(StatusCode::STATUS_OK);

           } catch (\Exception $e) {
               $rollSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
               throw $e;
           } finally {
               if (isset($rollScope)) {
                   $rollScope->detach();
               }
               if (isset($rollSpan)) {
                   $rollSpan->end();
               }
           }
           break;

       default:
           http_response_code(404);
           echo "404 Not Found";
           break;
   }
   $rootSpan->setStatus(StatusCode::STATUS_OK);

} catch (Exception $e) {
   $rootSpan->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
   error_log("Main error: " . $e->getMessage());
   http_response_code(500);
   echo "Error: " . $e->getMessage();
} finally {
   // End the root scope and span last
   $scope->detach();
   $rootSpan->end();
}

// Register shutdown function to handle final export
register_shutdown_function(function() use ($tracerProvider) {
   $tracerProvider->shutdown();
});
