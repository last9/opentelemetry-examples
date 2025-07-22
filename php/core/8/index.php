<?php

require __DIR__ . '/vendor/autoload.php';
use \Last9\Instrumentation;

// Initialize instrumentation
$instrumentation = Instrumentation::init(getenv('OTEL_SERVICE_NAME'));

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
