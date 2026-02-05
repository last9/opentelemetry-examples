package io.otel.rxjava.vertx.logging;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import org.slf4j.MDC;

/**
 * Utility for correlating logs with traces via SLF4J MDC.
 *
 * This class provides methods to automatically populate MDC with trace context
 * so that logs can be correlated with traces in your observability backend.
 *
 * MDC keys populated:
 * - trace_id: The W3C trace ID
 * - span_id: The current span ID
 * - trace_flags: The trace flags (sampled, etc.)
 *
 * Usage in logback.xml:
 * <pre>
 * &lt;pattern&gt;%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - trace_id=%X{trace_id} span_id=%X{span_id} - %msg%n&lt;/pattern&gt;
 * </pre>
 *
 * For JSON logging (recommended for production):
 * <pre>
 * {"timestamp": "%d", "level": "%level", "trace_id": "%X{trace_id}", "span_id": "%X{span_id}", "message": "%msg"}
 * </pre>
 */
public class MdcTraceCorrelation {

    public static final String TRACE_ID_KEY = "trace_id";
    public static final String SPAN_ID_KEY = "span_id";
    public static final String TRACE_FLAGS_KEY = "trace_flags";
    public static final String SERVICE_NAME_KEY = "service.name";

    private MdcTraceCorrelation() {
        // Utility class
    }

    /**
     * Update MDC with current span context.
     * Call this at the beginning of request handlers or when context changes.
     */
    public static void updateMdc() {
        Span span = Span.current();
        if (span != null && span.getSpanContext().isValid()) {
            SpanContext ctx = span.getSpanContext();
            MDC.put(TRACE_ID_KEY, ctx.getTraceId());
            MDC.put(SPAN_ID_KEY, ctx.getSpanId());
            MDC.put(TRACE_FLAGS_KEY, ctx.getTraceFlags().asHex());
        }
    }

    /**
     * Update MDC with specific span context
     */
    public static void updateMdc(SpanContext spanContext) {
        if (spanContext != null && spanContext.isValid()) {
            MDC.put(TRACE_ID_KEY, spanContext.getTraceId());
            MDC.put(SPAN_ID_KEY, spanContext.getSpanId());
            MDC.put(TRACE_FLAGS_KEY, spanContext.getTraceFlags().asHex());
        }
    }

    /**
     * Update MDC with service name
     */
    public static void setServiceName(String serviceName) {
        MDC.put(SERVICE_NAME_KEY, serviceName);
    }

    /**
     * Clear trace correlation from MDC
     */
    public static void clearMdc() {
        MDC.remove(TRACE_ID_KEY);
        MDC.remove(SPAN_ID_KEY);
        MDC.remove(TRACE_FLAGS_KEY);
    }

    /**
     * Execute a runnable with MDC populated from current context
     */
    public static void runWithMdc(Runnable runnable) {
        updateMdc();
        try {
            runnable.run();
        } finally {
            clearMdc();
        }
    }

    /**
     * Execute a callable with MDC populated from current context
     */
    public static <T> T callWithMdc(java.util.concurrent.Callable<T> callable) throws Exception {
        updateMdc();
        try {
            return callable.call();
        } finally {
            clearMdc();
        }
    }

    /**
     * Create a scope that keeps MDC in sync with the given OpenTelemetry context.
     * Use with try-with-resources to ensure MDC is cleaned up.
     */
    public static MdcScope makeCurrent(Context otelContext) {
        return new MdcScope(otelContext);
    }

    /**
     * A scope that manages both OpenTelemetry context and MDC together
     */
    public static class MdcScope implements AutoCloseable {
        private final Scope otelScope;
        private final String previousTraceId;
        private final String previousSpanId;
        private final String previousTraceFlags;

        MdcScope(Context otelContext) {
            // Save previous MDC values
            this.previousTraceId = MDC.get(TRACE_ID_KEY);
            this.previousSpanId = MDC.get(SPAN_ID_KEY);
            this.previousTraceFlags = MDC.get(TRACE_FLAGS_KEY);

            // Make the OTel context current
            this.otelScope = otelContext.makeCurrent();

            // Update MDC with new span context
            updateMdc();
        }

        @Override
        public void close() {
            // Restore previous MDC values
            restoreOrRemove(TRACE_ID_KEY, previousTraceId);
            restoreOrRemove(SPAN_ID_KEY, previousSpanId);
            restoreOrRemove(TRACE_FLAGS_KEY, previousTraceFlags);

            // Close OTel scope
            otelScope.close();
        }

        private void restoreOrRemove(String key, String value) {
            if (value != null) {
                MDC.put(key, value);
            } else {
                MDC.remove(key);
            }
        }
    }

    /**
     * Get the current trace ID from MDC, or null if not set
     */
    public static String getTraceId() {
        return MDC.get(TRACE_ID_KEY);
    }

    /**
     * Get the current span ID from MDC, or null if not set
     */
    public static String getSpanId() {
        return MDC.get(SPAN_ID_KEY);
    }
}
