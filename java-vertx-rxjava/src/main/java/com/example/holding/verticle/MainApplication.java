package com.example.holding.verticle;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.semconv.ResourceAttributes;
import io.vertx.core.DeploymentOptions;
import io.vertx.core.VertxOptions;
import io.vertx.rxjava3.core.Vertx;
import io.vertx.tracing.opentelemetry.OpenTelemetryOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MainApplication {
    private static final Logger log = LoggerFactory.getLogger(MainApplication.class);

    public static void main(String[] args) {
        // Initialize OpenTelemetry
        OpenTelemetry openTelemetry = initOpenTelemetry();

        // Create Vert.x with OpenTelemetry tracing enabled
        VertxOptions vertxOptions = new VertxOptions()
                .setTracingOptions(new OpenTelemetryOptions(openTelemetry));

        Vertx vertx = Vertx.vertx(vertxOptions);

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

    private static OpenTelemetry initOpenTelemetry() {
        String serviceName = System.getenv().getOrDefault("OTEL_SERVICE_NAME", "holding-service");
        String deploymentEnv = System.getenv().getOrDefault("OTEL_RESOURCE_ATTRIBUTES_DEPLOYMENT_ENVIRONMENT", "demo");
        String otlpEndpoint = System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318");
        String otlpHeaders = System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_HEADERS", "");

        log.info("Initializing OpenTelemetry with service: {}, environment: {}, endpoint: {}", serviceName, deploymentEnv, otlpEndpoint);

        // Build resource with service name and deployment environment
        Resource resource = Resource.getDefault()
                .merge(Resource.create(Attributes.of(
                        ResourceAttributes.SERVICE_NAME, serviceName,
                        ResourceAttributes.DEPLOYMENT_ENVIRONMENT, deploymentEnv
                )));

        // Build OTLP HTTP exporter
        OtlpHttpSpanExporter spanExporter = buildSpanExporter(otlpEndpoint, otlpHeaders);

        // Build tracer provider with batch processor
        SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
                .setResource(resource)
                .build();

        // Build and register OpenTelemetry SDK
        OpenTelemetrySdk openTelemetry = OpenTelemetrySdk.builder()
                .setTracerProvider(tracerProvider)
                .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                .buildAndRegisterGlobal();

        // Shutdown hook for graceful cleanup
        Runtime.getRuntime().addShutdownHook(new Thread(tracerProvider::close));

        log.info("OpenTelemetry initialized successfully");
        return openTelemetry;
    }

    private static OtlpHttpSpanExporter buildSpanExporter(String endpoint, String headers) {
        var builder = OtlpHttpSpanExporter.builder()
                .setEndpoint(endpoint + "/v1/traces");

        // Parse and add headers (format: "key1=value1,key2=value2")
        if (headers != null && !headers.isEmpty()) {
            for (String header : headers.split(",")) {
                String[] parts = header.split("=", 2);
                if (parts.length == 2) {
                    builder.addHeader(parts[0].trim(), parts[1].trim());
                }
            }
        }

        return builder.build();
    }
}
