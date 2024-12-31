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
use OpenTelemetry\API\Instrumentation\CachedInstrumentation;
use OpenTelemetry\Contrib\Instrumentation\MySqli\MysqliInstrumentation;

// Your existing OTLP setup
$transport = (new OtlpHttpTransportFactory())->create(getenv('OTEL_EXPORTER_OTLP_ENDPOINT'), 'application/json');
$exporter = new SpanExporter($transport);

// Create the BatchSpanProcessor with async options
$spanProcessor = new BatchSpanProcessor(
    $exporter,
    ClockFactory::getDefault()
);

$tracerProvider = new TracerProvider($spanProcessor);

// Add mysqli instrumentation
MysqliInstrumentation::register(new CachedInstrumentation('io.opentelemetry.contrib.php.mysqli'));

// Register the TracerProvider with Globals
Globals::registerInitializer(function (Configurator $configurator) use ($tracerProvider) {
    return $configurator->withTracerProvider($tracerProvider);
});

$method = $_SERVER['REQUEST_METHOD'];
$route = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$spanName = sprintf('%s %s', $method, $route);

// Now get the tracer from Globals
$tracer = Globals::tracerProvider()->getTracer('<your-app-name>');

$headers = getallheaders();
$contentLength = $headers['Content-Length'] ?? null;
$contentType = $headers['Content-Type'] ?? null;
$userAgent = $headers['User-Agent'] ?? null;
$referer = $headers['Referer'] ?? null;

// Create root span with complete HTTP attributes
$rootSpan = $tracer->spanBuilder($spanName)
   ->setSpanKind(SpanKind::KIND_SERVER)
   ->startSpan();

// Set comprehensive HTTP attributes following OpenTelemetry semantic conventions
$rootSpan->setAttributes([
    // Basic HTTP attributes
    'http.method' => $_SERVER['REQUEST_METHOD'],
    'http.target' => $_SERVER['REQUEST_URI'],
    'http.route' => parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH),
    'http.scheme' => isset($_SERVER['HTTPS']) ? 'https' : 'http',
    'http.status_code' => http_response_code(),

    // Server attributes
    'http.server_name' => $_SERVER['SERVER_NAME'] ?? 'unknown',
    'http.host' => $_SERVER['HTTP_HOST'] ?? 'unknown',
    'http.flavor' => substr($_SERVER['SERVER_PROTOCOL'] ?? 'HTTP/1.1', 5),

    // Client attributes
    'http.client_ip' => $_SERVER['REMOTE_ADDR'] ?? null,
    'http.user_agent' => $userAgent,

    // Request details
    'http.request.method' => $_SERVER['REQUEST_METHOD'],
    'http.request.body.size' => $contentLength,
    'http.request.content_type' => $contentType,
    'http.request.referer' => $referer,

    // Additional network context
    'net.host.name' => $_SERVER['SERVER_NAME'] ?? 'unknown',
    'net.host.port' => $_SERVER['SERVER_PORT'] ?? 80,
    'net.peer.ip' => $_SERVER['REMOTE_ADDR'] ?? null,
    'net.peer.port' => $_SERVER['REMOTE_PORT'] ?? null,

    // Optional: URL components
    'url.path' => parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH),
    'url.query' => parse_url($_SERVER['REQUEST_URI'], PHP_URL_QUERY),
    'url.scheme' => isset($_SERVER['HTTPS']) ? 'https' : 'http',
]);

// Also add trace context if present
foreach ($headers as $name => $value) {
    if (strtolower($name) === 'traceparent' || strtolower($name) === 'tracestate') {
        $rootSpan->setAttribute('http.request.header.' . strtolower($name), $value);
    }
}

// Create root context and activate it
$ctx = Context::getCurrent()->withContextValue($rootSpan);
$scope = $ctx->activate();

try {
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
   } catch (\Exception $e) {
       throw $e;
   }

   try {
       $mysqli->query("CREATE TABLE IF NOT EXISTS dice_rolls (
           id INT AUTO_INCREMENT PRIMARY KEY,
           roll_value INT NOT NULL,
           created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
       )");
   } catch (\Exception $e) {
       error_log("Error creating table: " . $e->getMessage());
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
                   throw $e;
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
                   $previousRolls = [];
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
