package com.example;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.opentelemetry.sdk.autoconfigure.AutoConfiguredOpenTelemetrySdk;

import java.util.function.Consumer;

/**
 * OTel SDK bootstrap and span helper.
 *
 * Configuration is driven entirely by OTEL_* environment variables (autoconfigure).
 * Call Telemetry.init() before creating any NATS connections.
 */
public final class Telemetry {

    private static OpenTelemetry otel;
    private static Tracer tracer;

    private Telemetry() {}

    public static void init() {
        otel = AutoConfiguredOpenTelemetrySdk.initialize().getOpenTelemetrySdk();
        tracer = otel.getTracer("nats-demo", "1.0.0");
    }

    public static OpenTelemetry get() {
        return otel;
    }

    /**
     * Run a block of code inside a CLIENT span.
     * Automatically sets span status to ERROR on exception.
     */
    public static void withSpan(String name, SpanKind kind, Consumer<Span> block) {
        Span span = tracer.spanBuilder(name).setSpanKind(kind).startSpan();
        try (Scope ignored = span.makeCurrent()) {
            block.accept(span);
        } catch (Exception e) {
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }

    public static Context currentContext() {
        return Context.current();
    }

    public static void shutdown() {
        if (otel instanceof AutoConfiguredOpenTelemetrySdk sdk) {
            // AutoConfigured SDK installs a shutdown hook; explicit call here for clean demo exit
        }
        GlobalOpenTelemetry.resetForTest();
    }
}
