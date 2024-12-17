# Laravel PHP 7.2 Manual-Instrumentation with OpenTelemetry and Last9

This guide explains how to use Last9's OpenTelemetry traces endpoint to ingest Laravel PHP application traces using OpenTelemetry Auto-Instrumentation.

## Prerequisites

- PHP 7.2
- Composer
- OpenTelemetry Manual Installation

## Installation Steps

### 1. PHP & Composer Setup

The following steps have been tested on Ubuntu 22.04 (LTS):

#### Install PHP
```bash
sudo apt-get update
sudo add-apt-repository ppa:ondrej/php
sudo apt install php7.2
```

#### Install Required PHP Modules
```bash
sudo apt-get install -y php7.2-cli php7.2-common php7.2-mysql php7.2-curl
```

#### Install Composer Globally
```bash
sudo apt update
sudo apt install curl php-cli php-mbstring git unzip
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
```

#### Verify Installation
```bash
php -v
composer -v
```

### 2. OpenTelemetry Manual

#### Install PECL Dependencies
```bash
sudo apt-get install gcc make autoconf
```

#### Install OpenTelemetry Extension
```bash
# Install build dependencies
sudo apt-get install gcc make autoconf php-dev

# Clone OpenTelemetry repository
git clone https://github.com/open-telemetry/opentelemetry-php-extension.git
cd opentelemetry-php-extension

# Prepare and compile
phpize
./configure
make
sudo make install
```

### Configure Dependencies
Update your `composer.json` with the following requirements:
```json
{
    "require": {
        "slim/slim": "^4",
        "slim/psr7": "^1",
        "guzzlehttp/guzzle": "^7.0"
    },
    "autoload": {
        "psr-4": {
            "App\\": "src/"
        }
    }
}

```

### Update Dependencies
```bash
rm composer.lock
rm -rf vendor
composer update
```

### Create Sample Application
Create an `index.php` file in your app directory with the following content:
```php
<?php
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Factory\AppFactory;
use GuzzleHttp\Client; // Use Guzzle for HTTP communication with OTLP collector

require __DIR__ . '/vendor/autoload.php';

// Replace with your OpenTelemetry collector endpoint
define('OTLP_COLLECTOR_URL', '<last9_otlp_endpoint>');

// Initialize Slim app
$app = AppFactory::create();

// Add routing middleware
$app->addRoutingMiddleware();

// Add error middleware
$errorMiddleware = $app->addErrorMiddleware(true, true, true);

// Function to create and send traces to the OpenTelemetry collector
function sendTrace($operationName, $attributes = []) {
    $traceId = bin2hex(random_bytes(16)); // Generate a random trace ID
    $spanId = bin2hex(random_bytes(8));  // Generate a random span ID
    $timestamp = (int)(microtime(true) * 1e6); // Get current timestamp in microseconds

    $tracePayload = [
        "resourceSpans" => [
            [
                "resource" => [
                    "attributes" => [
                        ["key" => "service.name", "value" => ["stringValue" => "demo-service"]]
                    ]
                ],
                "scopeSpans" => [
                    [
                        "spans" => [
                            [
                                "traceId" => $traceId,
                                "spanId" => $spanId,
                                "name" => $operationName,
                                "startTimeUnixNano" => $timestamp * 1000,
                                "endTimeUnixNano" => ($timestamp + 1000) * 1000, // Simulate 1ms duration
                                "attributes" => array_map(function ($key, $value) {
                                    return ["key" => $key, "value" => ["stringValue" => $value]];
                                }, array_keys($attributes), $attributes)
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ];

    $client = new Client();
    $response = $client->post(OTLP_COLLECTOR_URL, [
        'json' => $tracePayload,
        'headers' => ['Content-Type' => 'application/json'],
        'headers' => ['Authorization' => '<last9_auth_header>']
    ]);

    return $response->getStatusCode();
}

// Define routes
$app->get('/', function (Request $request, Response $response) {
    $response->getBody()->write("Hello World!");
    return $response;
});

$app->get('/rolldice', function (Request $request, Response $response) {
    $operationName = 'roll-dice';
    $result = random_int(1, 6);

    // Simulate tracing
    sendTrace($operationName, ['result' => strval($result)]);

    $response->getBody()->write("Rolled dice result: $result");
    return $response;
});
// Run the application
$app->run();
```

## Running and Testing

1. Start the PHP Application
```bash
php -S localhost:8080
```

2. Test the Application
Visit `http://localhost:8080/rolldice` in your browser. You should see a random number between 1 and 6.

## Viewing Traces

Trigger some requests to generate traces
View your traces in the [Last9 Dashboard](https://app.last9.io)


## Troubleshooting

If you have any questions or issues, please contact us on Discord or via Email.
