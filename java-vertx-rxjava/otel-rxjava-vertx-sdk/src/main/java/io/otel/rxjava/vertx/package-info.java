/**
 * OpenTelemetry SDK for RxJava3 + Vert.x applications.
 *
 * <h2>Quick Start</h2>
 * <pre>
 * // 1. Initialize the SDK (once at application startup)
 * OtelSdk sdk = OtelSdk.builder()
 *     .serviceName("my-service")
 *     .otlpEndpoint("http://localhost:4318")
 *     .build();
 *
 * // 2. Create Vert.x with tracing enabled
 * Vertx vertx = sdk.createVertx();
 *
 * // 3. Use Traced operations in your services
 * Traced.single("fetchUser", () -&gt; userRepository.findById(id))
 *
 * // 4. Use VertxTracing in handlers
 * VertxTracing.trace("processOrder", () -&gt; orderService.process(request))
 * </pre>
 *
 * <h2>Features</h2>
 * <ul>
 *   <li>Automatic context propagation across RxJava3 operators and schedulers</li>
 *   <li>Simple span creation with {@link io.otel.rxjava.vertx.operators.Traced}</li>
 *   <li>MDC-based log correlation with {@link io.otel.rxjava.vertx.logging.MdcTraceCorrelation}</li>
 *   <li>Vert.x handler integration with {@link io.otel.rxjava.vertx.context.VertxTracing}</li>
 * </ul>
 *
 * <h2>Log Correlation</h2>
 * Add trace_id and span_id to your logback pattern:
 * <pre>
 * &lt;pattern&gt;%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - trace_id=%X{trace_id} span_id=%X{span_id} - %msg%n&lt;/pattern&gt;
 * </pre>
 *
 * @see io.otel.rxjava.vertx.core.OtelSdk
 * @see io.otel.rxjava.vertx.operators.Traced
 * @see io.otel.rxjava.vertx.context.VertxTracing
 * @see io.otel.rxjava.vertx.logging.MdcTraceCorrelation
 */
package io.otel.rxjava.vertx;
