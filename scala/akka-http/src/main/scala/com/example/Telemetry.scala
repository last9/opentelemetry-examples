package com.example

import io.opentelemetry.api.GlobalOpenTelemetry
import io.opentelemetry.api.trace.{Span, SpanKind, StatusCode, Tracer}

object Telemetry:
  // The OTel Java agent installs the SDK into GlobalOpenTelemetry at JVM startup.
  // Application code only holds a reference to the API tracer — the SDK is never
  // imported directly, which keeps the compile-time dependency on opentelemetry-api only.
  val tracer: Tracer = GlobalOpenTelemetry.getTracer("akka-http-otel-example", "0.1.0")

  // Wraps a block in a span, propagates context, and handles errors.
  // Using makeCurrent() ensures child spans (e.g. JDBC, Kafka) created inside
  // the block are linked as children of this span.
  def withSpan[A](name: String, kind: SpanKind = SpanKind.INTERNAL)(block: Span => A): A =
    val span  = tracer.spanBuilder(name).setSpanKind(kind).startSpan()
    val scope = span.makeCurrent()
    try
      block(span)
    catch
      case e: Exception =>
        span.recordException(e)
        span.setStatus(StatusCode.ERROR, e.getMessage)
        throw e
    finally
      scope.close()
      span.end()
