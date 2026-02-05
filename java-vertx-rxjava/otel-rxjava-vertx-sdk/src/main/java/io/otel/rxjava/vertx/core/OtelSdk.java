package io.otel.rxjava.vertx.core;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.otlp.http.logs.OtlpHttpLogRecordExporter;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.exporter.otlp.logs.OtlpGrpcLogRecordExporter;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.logs.SdkLoggerProvider;
import io.opentelemetry.sdk.logs.export.BatchLogRecordProcessor;
import io.opentelemetry.sdk.logs.export.LogRecordExporter;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.sdk.trace.export.SpanExporter;
import io.opentelemetry.semconv.ResourceAttributes;
import io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender;
import io.otel.rxjava.vertx.operators.RxJava3ContextPropagation;
import io.vertx.core.VertxOptions;
import io.vertx.tracing.opentelemetry.OpenTelemetryOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Main SDK class for initializing OpenTelemetry with RxJava3 + Vert.x support.
 *
 * Usage:
 * <pre>
 * OtelSdk sdk = OtelSdk.builder()
 *     .serviceName("my-service")
 *     .otlpEndpoint("http://localhost:4318")
 *     .build();
 *
 * Vertx vertx = sdk.createVertx();
 * </pre>
 */
public class OtelSdk {
    private static final Logger log = LoggerFactory.getLogger(OtelSdk.class);

    private final OpenTelemetry openTelemetry;
    private final SdkTracerProvider tracerProvider;
    private final SdkLoggerProvider loggerProvider;
    private final String serviceName;
    private final Tracer tracer;

    private static OtelSdk instance;

    private OtelSdk(Builder builder) {
        this.serviceName = builder.serviceName;

        // Build resource
        Resource resource = Resource.getDefault()
                .merge(Resource.create(Attributes.builder()
                        .put(ResourceAttributes.SERVICE_NAME, builder.serviceName)
                        .put(ResourceAttributes.SERVICE_VERSION, builder.serviceVersion)
                        .put(ResourceAttributes.DEPLOYMENT_ENVIRONMENT, builder.environment)
                        .build()));

        // Build span exporter
        SpanExporter spanExporter = buildSpanExporter(builder);

        // Build tracer provider
        this.tracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(BatchSpanProcessor.builder(spanExporter)
                        .setMaxQueueSize(builder.maxQueueSize)
                        .setMaxExportBatchSize(builder.maxExportBatchSize)
                        .build())
                .setResource(resource)
                .build();

        // Build log exporter and logger provider
        LogRecordExporter logExporter = buildLogExporter(builder);
        this.loggerProvider = SdkLoggerProvider.builder()
                .addLogRecordProcessor(BatchLogRecordProcessor.builder(logExporter).build())
                .setResource(resource)
                .build();

        // Build OpenTelemetry SDK with both traces and logs
        OpenTelemetrySdk sdk = OpenTelemetrySdk.builder()
                .setTracerProvider(tracerProvider)
                .setLoggerProvider(loggerProvider)
                .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                .buildAndRegisterGlobal();

        this.openTelemetry = sdk;

        // Install the OpenTelemetry Logback appender
        OpenTelemetryAppender.install(sdk);

        this.tracer = openTelemetry.getTracer(serviceName);

        // Register RxJava3 context propagation hooks
        RxJava3ContextPropagation.enable();

        // Shutdown hook
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            log.info("Shutting down OpenTelemetry SDK");
            loggerProvider.close();
            tracerProvider.close();
        }));

        instance = this;
        log.info("OtelSdk initialized for service: {}, environment: {}, endpoint: {}",
                builder.serviceName, builder.environment, builder.otlpEndpoint);
    }

    /**
     * Get the singleton instance of OtelSdk
     */
    public static OtelSdk getInstance() {
        if (instance == null) {
            throw new IllegalStateException("OtelSdk not initialized. Call OtelSdk.builder().build() first.");
        }
        return instance;
    }

    /**
     * Get the OpenTelemetry instance
     */
    public OpenTelemetry getOpenTelemetry() {
        return openTelemetry;
    }

    /**
     * Get a tracer for creating spans
     */
    public Tracer getTracer() {
        return tracer;
    }

    /**
     * Get a tracer with a specific instrumentation name
     */
    public Tracer getTracer(String instrumentationName) {
        return openTelemetry.getTracer(instrumentationName);
    }

    /**
     * Get the service name
     */
    public String getServiceName() {
        return serviceName;
    }

    /**
     * Create VertxOptions configured with OpenTelemetry tracing
     */
    public VertxOptions createVertxOptions() {
        return new VertxOptions()
                .setTracingOptions(new OpenTelemetryOptions(openTelemetry));
    }

    /**
     * Create a Vert.x instance with OpenTelemetry tracing enabled
     */
    public io.vertx.rxjava3.core.Vertx createVertx() {
        return io.vertx.rxjava3.core.Vertx.vertx(createVertxOptions());
    }

    /**
     * Create a Vert.x instance with custom options merged with OpenTelemetry tracing
     */
    public io.vertx.rxjava3.core.Vertx createVertx(VertxOptions baseOptions) {
        baseOptions.setTracingOptions(new OpenTelemetryOptions(openTelemetry));
        return io.vertx.rxjava3.core.Vertx.vertx(baseOptions);
    }

    private SpanExporter buildSpanExporter(Builder builder) {
        if (builder.useGrpc) {
            var grpcBuilder = OtlpGrpcSpanExporter.builder()
                    .setEndpoint(builder.otlpEndpoint);

            if (builder.headers != null && !builder.headers.isEmpty()) {
                parseHeaders(builder.headers).forEach(grpcBuilder::addHeader);
            }

            return grpcBuilder.build();
        } else {
            String endpoint = builder.otlpEndpoint.endsWith("/v1/traces")
                    ? builder.otlpEndpoint
                    : builder.otlpEndpoint + "/v1/traces";

            var httpBuilder = OtlpHttpSpanExporter.builder()
                    .setEndpoint(endpoint);

            if (builder.headers != null && !builder.headers.isEmpty()) {
                parseHeaders(builder.headers).forEach(httpBuilder::addHeader);
            }

            return httpBuilder.build();
        }
    }

    private LogRecordExporter buildLogExporter(Builder builder) {
        if (builder.useGrpc) {
            var grpcBuilder = OtlpGrpcLogRecordExporter.builder()
                    .setEndpoint(builder.otlpEndpoint);

            if (builder.headers != null && !builder.headers.isEmpty()) {
                parseHeaders(builder.headers).forEach(grpcBuilder::addHeader);
            }

            return grpcBuilder.build();
        } else {
            String endpoint = builder.otlpEndpoint.endsWith("/v1/logs")
                    ? builder.otlpEndpoint
                    : builder.otlpEndpoint + "/v1/logs";

            var httpBuilder = OtlpHttpLogRecordExporter.builder()
                    .setEndpoint(endpoint);

            if (builder.headers != null && !builder.headers.isEmpty()) {
                parseHeaders(builder.headers).forEach(httpBuilder::addHeader);
            }

            return httpBuilder.build();
        }
    }

    private java.util.Map<String, String> parseHeaders(String headers) {
        java.util.Map<String, String> result = new java.util.HashMap<>();
        if (headers != null && !headers.isEmpty()) {
            for (String header : headers.split(",")) {
                String[] parts = header.split("=", 2);
                if (parts.length == 2) {
                    result.put(parts[0].trim(), parts[1].trim());
                }
            }
        }
        return result;
    }

    /**
     * Create a new builder for OtelSdk
     */
    public static Builder builder() {
        return new Builder();
    }

    /**
     * Builder for OtelSdk configuration
     */
    public static class Builder {
        private String serviceName = env("OTEL_SERVICE_NAME", "unknown-service");
        private String serviceVersion = env("OTEL_SERVICE_VERSION", "1.0.0");
        private String environment = env("OTEL_RESOURCE_ATTRIBUTES_DEPLOYMENT_ENVIRONMENT",
                env("DEPLOYMENT_ENV", "development"));
        private String otlpEndpoint = env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318");
        private String headers = env("OTEL_EXPORTER_OTLP_HEADERS", "");
        private boolean useGrpc = Boolean.parseBoolean(env("OTEL_EXPORTER_OTLP_PROTOCOL", "http").equals("grpc") ? "true" : "false");
        private int maxQueueSize = 2048;
        private int maxExportBatchSize = 512;

        private static String env(String key, String defaultValue) {
            String value = System.getenv(key);
            return (value != null && !value.isEmpty()) ? value : defaultValue;
        }

        public Builder serviceName(String serviceName) {
            this.serviceName = serviceName;
            return this;
        }

        public Builder serviceVersion(String serviceVersion) {
            this.serviceVersion = serviceVersion;
            return this;
        }

        public Builder environment(String environment) {
            this.environment = environment;
            return this;
        }

        public Builder otlpEndpoint(String otlpEndpoint) {
            this.otlpEndpoint = otlpEndpoint;
            return this;
        }

        public Builder headers(String headers) {
            this.headers = headers;
            return this;
        }

        public Builder useGrpc(boolean useGrpc) {
            this.useGrpc = useGrpc;
            return this;
        }

        public Builder maxQueueSize(int maxQueueSize) {
            this.maxQueueSize = maxQueueSize;
            return this;
        }

        public Builder maxExportBatchSize(int maxExportBatchSize) {
            this.maxExportBatchSize = maxExportBatchSize;
            return this;
        }

        public OtelSdk build() {
            return new OtelSdk(this);
        }
    }
}
