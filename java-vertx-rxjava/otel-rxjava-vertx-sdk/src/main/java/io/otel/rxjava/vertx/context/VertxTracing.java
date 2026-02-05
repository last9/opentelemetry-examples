package io.otel.rxjava.vertx.context;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.otel.rxjava.vertx.logging.MdcTraceCorrelation;
import io.reactivex.rxjava3.core.Completable;
import io.reactivex.rxjava3.core.Maybe;
import io.reactivex.rxjava3.core.Single;
import io.vertx.rxjava3.ext.web.RoutingContext;

import java.util.Map;
import java.util.function.Consumer;
import java.util.function.Function;

/**
 * Vert.x handler integration for OpenTelemetry tracing.
 *
 * Provides utilities to create traced handlers and propagate context through
 * Vert.x request processing.
 *
 * Usage:
 * <pre>
 * // Simple traced handler
 * router.get("/api/users").handler(VertxTracing.traced(this::handleGetUsers));
 *
 * // Handler returning Single
 * router.get("/api/user/:id").handler(VertxTracing.tracedSingle(this::handleGetUser));
 * </pre>
 */
public class VertxTracing {

    private static final String DEFAULT_TRACER_NAME = "vertx-handlers";

    private VertxTracing() {
        // Utility class
    }

    /**
     * Wrap a Vert.x handler to ensure MDC is populated with trace context
     */
    public static Consumer<RoutingContext> traced(Consumer<RoutingContext> handler) {
        return ctx -> {
            MdcTraceCorrelation.updateMdc();
            try {
                handler.accept(ctx);
            } finally {
                // Don't clear MDC here as async operations may still need it
            }
        };
    }

    /**
     * Create a traced handler that processes requests with a Single
     */
    public static <T> Consumer<RoutingContext> tracedSingle(
            Function<RoutingContext, Single<T>> handler,
            ResponseWriter<T> responseWriter) {
        return ctx -> {
            MdcTraceCorrelation.updateMdc();

            handler.apply(ctx)
                    .doOnSubscribe(d -> MdcTraceCorrelation.updateMdc())
                    .subscribe(
                            result -> {
                                MdcTraceCorrelation.updateMdc();
                                responseWriter.write(ctx, result);
                            },
                            error -> {
                                MdcTraceCorrelation.updateMdc();
                                handleError(ctx, error);
                            }
                    );
        };
    }

    /**
     * Create a child span for an operation within a handler
     */
    public static Span startSpan(String spanName) {
        return startSpan(spanName, SpanKind.INTERNAL, Map.of());
    }

    /**
     * Create a child span with attributes
     */
    public static Span startSpan(String spanName, Map<String, Object> attributes) {
        return startSpan(spanName, SpanKind.INTERNAL, attributes);
    }

    /**
     * Create a child span with kind and attributes
     */
    public static Span startSpan(String spanName, SpanKind kind, Map<String, Object> attributes) {
        Tracer tracer = GlobalOpenTelemetry.getTracer(DEFAULT_TRACER_NAME);
        Context parentContext = Context.current();

        var spanBuilder = tracer.spanBuilder(spanName)
                .setParent(parentContext)
                .setSpanKind(kind);

        attributes.forEach((key, value) -> {
            if (value instanceof String) {
                spanBuilder.setAttribute(AttributeKey.stringKey(key), (String) value);
            } else if (value instanceof Long) {
                spanBuilder.setAttribute(AttributeKey.longKey(key), (Long) value);
            } else if (value instanceof Integer) {
                spanBuilder.setAttribute(AttributeKey.longKey(key), ((Integer) value).longValue());
            } else if (value instanceof Double) {
                spanBuilder.setAttribute(AttributeKey.doubleKey(key), (Double) value);
            } else if (value instanceof Boolean) {
                spanBuilder.setAttribute(AttributeKey.booleanKey(key), (Boolean) value);
            } else if (value != null) {
                spanBuilder.setAttribute(AttributeKey.stringKey(key), value.toString());
            }
        });

        return spanBuilder.startSpan();
    }

    /**
     * Execute a traced operation within a handler.
     * Creates a child span and propagates context.
     */
    public static <T> Single<T> trace(String spanName, java.util.function.Supplier<Single<T>> operation) {
        return Single.defer(() -> {
            Span span = startSpan(spanName);
            Context spanContext = Context.current().with(span);

            try (MdcTraceCorrelation.MdcScope scope = MdcTraceCorrelation.makeCurrent(spanContext)) {
                return operation.get()
                        .doOnSuccess(result -> {
                            span.setStatus(StatusCode.OK);
                            span.end();
                        })
                        .doOnError(error -> {
                            span.setStatus(StatusCode.ERROR, error.getMessage());
                            span.recordException(error);
                            span.end();
                        });
            }
        });
    }

    /**
     * Execute a traced operation within a handler with attributes
     */
    public static <T> Single<T> trace(String spanName, Map<String, Object> attributes, java.util.function.Supplier<Single<T>> operation) {
        return Single.defer(() -> {
            Span span = startSpan(spanName, attributes);
            Context spanContext = Context.current().with(span);

            try (MdcTraceCorrelation.MdcScope scope = MdcTraceCorrelation.makeCurrent(spanContext)) {
                return operation.get()
                        .doOnSuccess(result -> {
                            span.setStatus(StatusCode.OK);
                            span.end();
                        })
                        .doOnError(error -> {
                            span.setStatus(StatusCode.ERROR, error.getMessage());
                            span.recordException(error);
                            span.end();
                        });
            }
        });
    }

    /**
     * Add attributes to the current span
     */
    public static void addAttributes(Map<String, Object> attributes) {
        Span span = Span.current();
        if (span != null) {
            attributes.forEach((key, value) -> {
                if (value instanceof String) {
                    span.setAttribute(AttributeKey.stringKey(key), (String) value);
                } else if (value instanceof Long) {
                    span.setAttribute(AttributeKey.longKey(key), (Long) value);
                } else if (value instanceof Integer) {
                    span.setAttribute(AttributeKey.longKey(key), ((Integer) value).longValue());
                } else if (value instanceof Double) {
                    span.setAttribute(AttributeKey.doubleKey(key), (Double) value);
                } else if (value instanceof Boolean) {
                    span.setAttribute(AttributeKey.booleanKey(key), (Boolean) value);
                } else if (value != null) {
                    span.setAttribute(AttributeKey.stringKey(key), value.toString());
                }
            });
        }
    }

    /**
     * Add a single attribute to the current span
     */
    public static void addAttribute(String key, String value) {
        Span span = Span.current();
        if (span != null) {
            span.setAttribute(key, value);
        }
    }

    /**
     * Add an event to the current span
     */
    public static void addEvent(String eventName) {
        Span span = Span.current();
        if (span != null) {
            span.addEvent(eventName);
        }
    }

    /**
     * Add an event with attributes to the current span
     */
    public static void addEvent(String eventName, Map<String, Object> attributes) {
        Span span = Span.current();
        if (span != null) {
            var attrBuilder = io.opentelemetry.api.common.Attributes.builder();
            attributes.forEach((key, value) -> {
                if (value instanceof String) {
                    attrBuilder.put(AttributeKey.stringKey(key), (String) value);
                } else if (value instanceof Long) {
                    attrBuilder.put(AttributeKey.longKey(key), (Long) value);
                } else if (value != null) {
                    attrBuilder.put(AttributeKey.stringKey(key), value.toString());
                }
            });
            span.addEvent(eventName, attrBuilder.build());
        }
    }

    /**
     * Record an exception on the current span
     */
    public static void recordException(Throwable exception) {
        Span span = Span.current();
        if (span != null) {
            span.recordException(exception);
            span.setStatus(StatusCode.ERROR, exception.getMessage());
        }
    }

    /**
     * Default error handler for Vert.x requests
     */
    public static void handleError(RoutingContext ctx, Throwable error) {
        recordException(error);
        ctx.response()
                .setStatusCode(500)
                .putHeader("Content-Type", "application/json")
                .end("{\"error\": \"" + error.getMessage() + "\"}");
    }

    /**
     * Interface for writing responses
     */
    @FunctionalInterface
    public interface ResponseWriter<T> {
        void write(RoutingContext ctx, T result);
    }
}
