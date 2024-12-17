# Laravel PHP 8.1 Auto-Instrumentation with OpenTelemetry and Last9

This guide explains how to use Last9's OpenTelemetry traces endpoint to ingest Laravel PHP application traces using OpenTelemetry Auto-Instrumentation.

## Prerequisites

- PHP 8.0 or higher
- Composer
- PECL

## Installation Steps

### 1. PHP & Composer Setup

The following steps have been tested on Ubuntu 22.04 (LTS):

#### Install PHP
```bash
sudo apt-get update
sudo add-apt-repository ppa:ondrej/php
sudo apt install php8.1
```

#### Install Required PHP Modules
```bash
sudo apt-get install -y php8.1-cli php8.1-common php8.1-mysql php8.1-zip php8.1-gd php8.1-mbstring php8.1-curl php8.1-xml php8.1-bcmath
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

### 2. PECL Setup

#### Install PECL Dependencies
```bash
sudo apt-get install gcc make autoconf
```

#### Install OpenTelemetry Extension
```bash
pecl install opentelemetry
```

#### Configure PHP Extension
Add the following to your php.ini file:
```ini
[opentelemetry]
extension=opentelemetry.so
```

#### Verify Extension
```bash
php -m | grep opentelemetry
```

## Example Application Setup

### Create New Laravel Project
```bash
composer create-project --prefer-dist laravel/laravel sample-app "11.*"
cd sample-app
```

### Configure Dependencies
Update your `composer.json` with the following requirements:
```json
{
    "require": {
        "slim/slim": "^4",
        "slim/psr7": "^1",
        "open-telemetry/sdk": "^1.1",
        "open-telemetry/opentelemetry-auto-laravel": "^1.0",
        "open-telemetry/exporter-otlp": "^1.0",
        "guzzlehttp/guzzle": "^7.0",
        "open-telemetry/transport-grpc": "^1.1",
        "php-http/guzzle7-adapter": "^1.1"
    },
    "config": {
        "optimize-autoloader": true,
        "preferred-install": "dist",
        "sort-packages": true,
        "allow-plugins": {
            "pestphp/pest-plugin": true,
            "php-http/discovery": false,
            "tbachert/spi": true
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

### Configure Environment
Add the following to your `.env` file:
```env
OTEL_PHP_AUTOLOAD_ENABLED=true
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none
OTEL_EXPORTER_OTLP_ENDPOINT="<last9_otlp_endpoint>"
OTEL_EXPORTER_OTLP_HEADERS="Authorization=<last9_auth_header>"
OTEL_SERVICE_NAME=otel-laravel-app
OTEL_TRACES_EXPORTER=console
```

Note: Initially set `OTEL_TRACES_EXPORTER=console` to verify trace generation in the console. Once verified, change it to `otlp` to send traces to Last9.

### Create Sample Application
Create an `index.php` file in your sample-app directory with the following content:
```php
<?php
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Factory\AppFactory;

require __DIR__ . '/vendor/autoload.php';

$app = AppFactory::create();

$app->get('/rolldice', function (Request $request, Response $response) {
    $result = random_int(1, 6);
    $response->getBody()->write(strval($result));
    return $response;
});

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

After testing with `console` exporter, switch to `otlp` in your `.env` file
Trigger some requests to generate traces
View your traces in the [Last9 Dashboard](https://app.last9.io)


## Troubleshooting

If you have any questions or issues, please contact us on Discord or via Email.
