package io.temporal.example.worker;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.semconv.ServiceAttributes;
import io.opentracing.Tracer;
import io.opentracing.util.GlobalTracer;
import io.opentelemetry.opentracingshim.OpenTracingShim;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class TracingConfig {

    private static final Logger logger = LoggerFactory.getLogger(TracingConfig.class);

    private static OpenTelemetrySdk openTelemetrySdk;

    /**
     * Initialize OpenTelemetry and register the OpenTracing shim as GlobalTracer.
     * This allows Temporal's OpenTracing interceptors to work with OpenTelemetry.
     */
    public static void initializeTracing() {
        String serviceName = System.getenv().getOrDefault("OTEL_SERVICE_NAME", "java-temporal");
        String otlpEndpoint = System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_ENDPOINT", "https://otlp-aps1.last9.io");
        String otlpHeaders = System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_HEADERS", "");
        String deploymentEnv = System.getenv().getOrDefault("DEPLOYMENT_ENVIRONMENT", "demo");

        logger.info("Initializing OpenTelemetry tracing: service={}, endpoint={}, environment={}",
                serviceName, otlpEndpoint, deploymentEnv);

        // Create resource with service name and deployment environment
        Resource resource = Resource.getDefault()
                .merge(Resource.create(Attributes.of(
                        ServiceAttributes.SERVICE_NAME, serviceName,
                        AttributeKey.stringKey("deployment.environment"), deploymentEnv
                )));

        // Create OTLP HTTP exporter builder (for sending directly to Last9)
        var exporterBuilder = OtlpHttpSpanExporter.builder()
                .setEndpoint(otlpEndpoint + "/v1/traces");

        // Add authorization header if provided
        if (!otlpHeaders.isEmpty()) {
            // Parse headers in format: key1=value1,key2=value2
            for (String header : otlpHeaders.split(",")) {
                String[] parts = header.split("=", 2);
                if (parts.length == 2) {
                    exporterBuilder.addHeader(parts[0].trim(), parts[1].trim());
                }
            }
        }

        OtlpHttpSpanExporter spanExporter = exporterBuilder.build();

        // Create tracer provider with batch processor
        SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
                .setResource(resource)
                .build();

        // Build OpenTelemetry SDK
        openTelemetrySdk = OpenTelemetrySdk.builder()
                .setTracerProvider(tracerProvider)
                .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                .build();

        // Create OpenTracing shim from OpenTelemetry
        Tracer openTracingTracer = OpenTracingShim.createTracerShim(openTelemetrySdk);

        // Register as GlobalTracer for Temporal interceptors
        GlobalTracer.registerIfAbsent(openTracingTracer);

        // Register shutdown hook
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            logger.info("Shutting down OpenTelemetry...");
            openTelemetrySdk.close();
        }));

        logger.info("OpenTelemetry tracing initialized successfully");
    }

    public static OpenTelemetry getOpenTelemetry() {
        return openTelemetrySdk;
    }
}
