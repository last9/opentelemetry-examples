package io.otel.rxjava.vertx.operators;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.reactivex.rxjava3.core.Completable;
import io.reactivex.rxjava3.core.Maybe;
import io.reactivex.rxjava3.core.Single;

import java.util.Map;
import java.util.concurrent.Callable;
import java.util.function.Supplier;

/**
 * Utility class for creating traced RxJava operations.
 *
 * Provides static methods to wrap RxJava operations with OpenTelemetry spans.
 *
 * Usage:
 * <pre>
 * // Simple traced Single
 * Traced.single("fetchUser", () -> userRepository.findById(id))
 *
 * // With attributes
 * Traced.single("fetchUser", Map.of("user.id", id), () -> userRepository.findById(id))
 *
 * // Traced callable (sync operation)
 * Traced.call("processData", () -> processor.process(data))
 * </pre>
 */
public class Traced {

    private static final String DEFAULT_TRACER_NAME = "traced-operations";

    private Traced() {
        // Utility class
    }

    // ============ Single operations ============

    /**
     * Wrap a Single-returning supplier with a traced span
     */
    public static <T> Single<T> single(String spanName, Supplier<Single<T>> operation) {
        return single(spanName, Map.of(), SpanKind.INTERNAL, operation);
    }

    /**
     * Wrap a Single-returning supplier with a traced span and attributes
     */
    public static <T> Single<T> single(String spanName, Map<String, Object> attributes, Supplier<Single<T>> operation) {
        return single(spanName, attributes, SpanKind.INTERNAL, operation);
    }

    /**
     * Wrap a Single-returning supplier with a traced span, attributes, and kind
     */
    public static <T> Single<T> single(String spanName, Map<String, Object> attributes, SpanKind kind, Supplier<Single<T>> operation) {
        return Single.defer(() -> {
            Tracer tracer = GlobalOpenTelemetry.getTracer(DEFAULT_TRACER_NAME);
            Context parentContext = Context.current();

            var spanBuilder = tracer.spanBuilder(spanName)
                    .setParent(parentContext)
                    .setSpanKind(kind);

            // Add attributes
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

            Span span = spanBuilder.startSpan();

            try (Scope scope = span.makeCurrent()) {
                return operation.get()
                        .doOnSuccess(result -> span.setStatus(StatusCode.OK).end())
                        .doOnError(error -> {
                            span.setStatus(StatusCode.ERROR, error.getMessage());
                            span.recordException(error);
                            span.end();
                        });
            } catch (Exception e) {
                span.setStatus(StatusCode.ERROR, e.getMessage());
                span.recordException(e);
                span.end();
                return Single.error(e);
            }
        });
    }

    // ============ Maybe operations ============

    /**
     * Wrap a Maybe-returning supplier with a traced span
     */
    public static <T> Maybe<T> maybe(String spanName, Supplier<Maybe<T>> operation) {
        return maybe(spanName, Map.of(), SpanKind.INTERNAL, operation);
    }

    /**
     * Wrap a Maybe-returning supplier with a traced span and attributes
     */
    public static <T> Maybe<T> maybe(String spanName, Map<String, Object> attributes, Supplier<Maybe<T>> operation) {
        return maybe(spanName, attributes, SpanKind.INTERNAL, operation);
    }

    /**
     * Wrap a Maybe-returning supplier with a traced span, attributes, and kind
     */
    public static <T> Maybe<T> maybe(String spanName, Map<String, Object> attributes, SpanKind kind, Supplier<Maybe<T>> operation) {
        return Maybe.defer(() -> {
            Tracer tracer = GlobalOpenTelemetry.getTracer(DEFAULT_TRACER_NAME);
            Context parentContext = Context.current();

            var spanBuilder = tracer.spanBuilder(spanName)
                    .setParent(parentContext)
                    .setSpanKind(kind);

            attributes.forEach((key, value) -> addAttribute(spanBuilder, key, value));

            Span span = spanBuilder.startSpan();

            try (Scope scope = span.makeCurrent()) {
                return operation.get()
                        .doOnSuccess(result -> span.setStatus(StatusCode.OK).end())
                        .doOnComplete(() -> span.setStatus(StatusCode.OK).end())
                        .doOnError(error -> {
                            span.setStatus(StatusCode.ERROR, error.getMessage());
                            span.recordException(error);
                            span.end();
                        });
            } catch (Exception e) {
                span.setStatus(StatusCode.ERROR, e.getMessage());
                span.recordException(e);
                span.end();
                return Maybe.error(e);
            }
        });
    }

    // ============ Completable operations ============

    /**
     * Wrap a Completable-returning supplier with a traced span
     */
    public static Completable completable(String spanName, Supplier<Completable> operation) {
        return completable(spanName, Map.of(), SpanKind.INTERNAL, operation);
    }

    /**
     * Wrap a Completable-returning supplier with a traced span and attributes
     */
    public static Completable completable(String spanName, Map<String, Object> attributes, Supplier<Completable> operation) {
        return completable(spanName, attributes, SpanKind.INTERNAL, operation);
    }

    /**
     * Wrap a Completable-returning supplier with a traced span, attributes, and kind
     */
    public static Completable completable(String spanName, Map<String, Object> attributes, SpanKind kind, Supplier<Completable> operation) {
        return Completable.defer(() -> {
            Tracer tracer = GlobalOpenTelemetry.getTracer(DEFAULT_TRACER_NAME);
            Context parentContext = Context.current();

            var spanBuilder = tracer.spanBuilder(spanName)
                    .setParent(parentContext)
                    .setSpanKind(kind);

            attributes.forEach((key, value) -> addAttribute(spanBuilder, key, value));

            Span span = spanBuilder.startSpan();

            try (Scope scope = span.makeCurrent()) {
                return operation.get()
                        .doOnComplete(() -> span.setStatus(StatusCode.OK).end())
                        .doOnError(error -> {
                            span.setStatus(StatusCode.ERROR, error.getMessage());
                            span.recordException(error);
                            span.end();
                        });
            } catch (Exception e) {
                span.setStatus(StatusCode.ERROR, e.getMessage());
                span.recordException(e);
                span.end();
                return Completable.error(e);
            }
        });
    }

    // ============ Callable (sync) operations ============

    /**
     * Wrap a synchronous callable with a traced span, returning a Single
     */
    public static <T> Single<T> call(String spanName, Callable<T> callable) {
        return call(spanName, Map.of(), callable);
    }

    /**
     * Wrap a synchronous callable with a traced span and attributes, returning a Single
     */
    public static <T> Single<T> call(String spanName, Map<String, Object> attributes, Callable<T> callable) {
        return Single.fromCallable(() -> {
            Tracer tracer = GlobalOpenTelemetry.getTracer(DEFAULT_TRACER_NAME);
            Context parentContext = Context.current();

            var spanBuilder = tracer.spanBuilder(spanName)
                    .setParent(parentContext)
                    .setSpanKind(SpanKind.INTERNAL);

            attributes.forEach((key, value) -> addAttribute(spanBuilder, key, value));

            Span span = spanBuilder.startSpan();

            try (Scope scope = span.makeCurrent()) {
                T result = callable.call();
                span.setStatus(StatusCode.OK);
                return result;
            } catch (Exception e) {
                span.setStatus(StatusCode.ERROR, e.getMessage());
                span.recordException(e);
                throw e;
            } finally {
                span.end();
            }
        });
    }

    // ============ Run (void sync) operations ============

    /**
     * Wrap a void operation with a traced span, returning a Completable
     */
    public static Completable run(String spanName, Runnable runnable) {
        return run(spanName, Map.of(), runnable);
    }

    /**
     * Wrap a void operation with a traced span and attributes, returning a Completable
     */
    public static Completable run(String spanName, Map<String, Object> attributes, Runnable runnable) {
        return Completable.fromAction(() -> {
            Tracer tracer = GlobalOpenTelemetry.getTracer(DEFAULT_TRACER_NAME);
            Context parentContext = Context.current();

            var spanBuilder = tracer.spanBuilder(spanName)
                    .setParent(parentContext)
                    .setSpanKind(SpanKind.INTERNAL);

            attributes.forEach((key, value) -> addAttribute(spanBuilder, key, value));

            Span span = spanBuilder.startSpan();

            try (Scope scope = span.makeCurrent()) {
                runnable.run();
                span.setStatus(StatusCode.OK);
            } catch (Exception e) {
                span.setStatus(StatusCode.ERROR, e.getMessage());
                span.recordException(e);
                throw e;
            } finally {
                span.end();
            }
        });
    }

    // ============ Helper methods ============

    private static void addAttribute(io.opentelemetry.api.trace.SpanBuilder spanBuilder, String key, Object value) {
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
    }
}
