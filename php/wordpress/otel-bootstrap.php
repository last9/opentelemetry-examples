<?php
/**
 * OpenTelemetry Bootstrap File for WordPress
 *
 * This file is auto-prepended before WordPress loads, enabling
 * zero-code OpenTelemetry instrumentation.
 *
 * The auto-instrumentation packages automatically capture:
 * - WordPress hooks and actions
 * - Database queries (PDO/MySQLi)
 * - HTTP client requests (cURL)
 * - Request/response lifecycle
 */

// Only load if the OTel vendor directory exists
$otelAutoloadPath = '/var/www/vendor/autoload.php';

if (file_exists($otelAutoloadPath)) {
    require_once $otelAutoloadPath;

    // Optional: Add custom resource attributes
    // These will be attached to all spans
    if (class_exists('\OpenTelemetry\SDK\Resource\ResourceInfoFactory')) {
        // Resource attributes are configured via OTEL_RESOURCE_ATTRIBUTES env var
        // Example: OTEL_RESOURCE_ATTRIBUTES="service.namespace=production,host.name=wp-server-1"
    }
}
