package com.example.holding.verticle;

import io.otel.rxjava.vertx.core.OtelSdk;
import io.vertx.core.DeploymentOptions;
import io.vertx.rxjava3.core.Vertx;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Main application entry point with OtelSdk integration.
 *
 * The SDK automatically:
 * - Initializes OpenTelemetry with OTLP exporter
 * - Enables RxJava3 context propagation
 * - Configures Vert.x with tracing
 */
public class MainApplication {
    private static final Logger log = LoggerFactory.getLogger(MainApplication.class);

    public static void main(String[] args) {
        // Initialize OtelSdk - reads config from environment variables:
        // OTEL_SERVICE_NAME, OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_HEADERS
        OtelSdk sdk = OtelSdk.builder()
                .serviceName(System.getenv().getOrDefault("OTEL_SERVICE_NAME", "holding-service"))
                .environment(System.getenv().getOrDefault("DEPLOYMENT_ENV", "demo"))
                .otlpEndpoint(System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"))
                .headers(System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_HEADERS", ""))
                .build();

        // Create Vert.x with OpenTelemetry tracing enabled
        Vertx vertx = sdk.createVertx();

        DeploymentOptions options = new DeploymentOptions();

        vertx.rxDeployVerticle(new MainVerticle(), options)
                .subscribe(
                        id -> log.info("MainVerticle deployed successfully with id: {}", id),
                        err -> {
                            log.error("Failed to deploy MainVerticle", err);
                            System.exit(1);
                        }
                );
    }
}
