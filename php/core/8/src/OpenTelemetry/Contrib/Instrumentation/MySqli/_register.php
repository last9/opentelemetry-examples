<?php

declare(strict_types=1);

use OpenTelemetry\API\Instrumentation\CachedInstrumentation;
use OpenTelemetry\Contrib\Instrumentation\MySqli\MysqliInstrumentation;

if (extension_loaded('mysqli')) {
    MysqliInstrumentation::register(new CachedInstrumentation('io.opentelemetry.contrib.php.mysqli'));
}
