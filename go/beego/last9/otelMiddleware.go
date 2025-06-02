package last9

import (
	"net/http"
	"strings"

	"log"

	beego "github.com/beego/beego/v2/server/web"
	beecontext "github.com/beego/beego/v2/server/web/context"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// BeegoOtelMiddleware returns a Beego filter for OpenTelemetry tracing
func BeegoOtelMiddleware(service string) beego.FilterFunc {
	return func(ctx *beecontext.Context) {
		log.Printf("[otel] BeegoOtelMiddleware: %s %s", ctx.Request.Method, ctx.Request.URL.Path)
		propagator := otel.GetTextMapPropagator()
		carrier := propagation.HeaderCarrier(ctx.Request.Header)
		ctxReq := propagator.Extract(ctx.Request.Context(), carrier)

		tracer := otel.Tracer(service)
		spanName := normalizePath(ctx.Request.URL.Path)
		attrs := []attribute.KeyValue{
			semconv.ServiceNameKey.String(service),
			semconv.HTTPRequestMethodKey.String(ctx.Request.Method),
			semconv.HTTPRouteKey.String(ctx.Request.URL.Path),
			semconv.URLFullKey.String(ctx.Request.URL.String()),
			semconv.URLSchemeKey.String(ctx.Request.URL.Scheme),
		}
		if ua := ctx.Request.UserAgent(); ua != "" {
			attrs = append(attrs, semconv.UserAgentOriginalKey.String(ua))
		}
		if host := ctx.Request.Host; host != "" {
			attrs = append(attrs, semconv.ServerAddressKey.String(host))
		}
		spanCtx, span := tracer.Start(ctxReq, spanName, trace.WithAttributes(attrs...), trace.WithSpanKind(trace.SpanKindServer))
		log.Printf("[otel] Started HTTP span: %s", spanName)
		// Inject the span context into the request headers
		propagator.Inject(spanCtx, carrier)
		ctx.Request = ctx.Request.WithContext(spanCtx)
		ctx.Input.SetData("otel-span", span)

		// Defer ending the span after the handler has run
		defer func() {
			status := ctx.ResponseWriter.Status
			log.Printf("[otel] Ending HTTP span: %s, status: %d", ctx.Request.URL.Path, status)
			span.SetAttributes(
				semconv.HTTPResponseStatusCodeKey.Int(status),
				attribute.String("otel.debug", "http-root"),
			)
			span.SetStatus(httpStatusCodeToSpanStatus(status), http.StatusText(status))
			span.End()
		}()
	}
}

// BeegoOtelStartMiddleware injects context and starts the span (BeforeRouter)
func BeegoOtelStartMiddleware(service string) beego.FilterFunc {
	return func(ctx *beecontext.Context) {
		log.Printf("[otel] BeegoOtelStartMiddleware: %s %s", ctx.Request.Method, ctx.Request.URL.Path)
		propagator := otel.GetTextMapPropagator()
		carrier := propagation.HeaderCarrier(ctx.Request.Header)
		ctxReq := propagator.Extract(ctx.Request.Context(), carrier)

		tracer := otel.Tracer(service)
		spanName := normalizePath(ctx.Request.URL.Path)
		attrs := []attribute.KeyValue{
			semconv.ServiceNameKey.String(service),
			semconv.HTTPRequestMethodKey.String(ctx.Request.Method),
			semconv.HTTPRouteKey.String(ctx.Request.URL.Path),
			semconv.URLFullKey.String(ctx.Request.URL.String()),
			semconv.URLSchemeKey.String(ctx.Request.URL.Scheme),
		}
		if ua := ctx.Request.UserAgent(); ua != "" {
			attrs = append(attrs, semconv.UserAgentOriginalKey.String(ua))
		}
		if host := ctx.Request.Host; host != "" {
			attrs = append(attrs, semconv.ServerAddressKey.String(host))
		}
		spanCtx, span := tracer.Start(ctxReq, spanName, trace.WithAttributes(attrs...), trace.WithSpanKind(trace.SpanKindServer))
		log.Printf("[otel] Started HTTP span: %s", spanName)
		// Inject the span context into the request headers
		propagator.Inject(spanCtx, carrier)
		ctx.Request = ctx.Request.WithContext(spanCtx)
		ctx.Input.SetData("otel-span", span)
	}
}

// BeegoOtelEndMiddleware sets status code and ends the span (AfterExec)
func BeegoOtelEndMiddleware() beego.FilterFunc {
	return func(ctx *beecontext.Context) {
		spanAny := ctx.Input.GetData("otel-span")
		if spanAny == nil {
			log.Println("[otel] No span found in context for BeegoOtelEndMiddleware")
			return
		}
		span, ok := spanAny.(trace.Span)
		if !ok {
			log.Println("[otel] otel-span in context is not a trace.Span")
			return
		}
		status := ctx.ResponseWriter.Status
		log.Printf("[otel] Ending HTTP span: %s, status: %d", ctx.Request.URL.Path, status)
		span.SetAttributes(
			semconv.HTTPResponseStatusCodeKey.Int(status),
			attribute.String("otel.debug", "http-root"),
		)
		span.SetStatus(httpStatusCodeToSpanStatus(status), http.StatusText(status))
		span.End()
	}
}

func httpStatusCodeToSpanStatus(code int) codes.Code {
	if code < 100 || code >= 600 {
		return codes.Error
	}
	if code >= 400 {
		return codes.Error
	}
	return codes.Ok
}

func normalizePath(path string) string {
	// Replace numeric IDs and UUIDs with placeholders for better span grouping
	path = strings.ReplaceAll(path, "/[0-9]+", "/:id")
	// Add more normalization as needed
	return path
}

// WrapBeegoHandler wraps a Beego handler/controller method with OpenTelemetry tracing.
func WrapBeegoHandler(service string, handler func(ctx *beego.Controller)) func(ctx *beego.Controller) {
	return func(ctx *beego.Controller) {
		propagator := otel.GetTextMapPropagator()
		carrier := propagation.HeaderCarrier(ctx.Ctx.Request.Header)
		ctxReq := propagator.Extract(ctx.Ctx.Request.Context(), carrier)

		tracer := otel.Tracer(service)
		spanName := normalizePath(ctx.Ctx.Request.URL.Path)
		attrs := []attribute.KeyValue{
			semconv.ServiceNameKey.String(service),
			semconv.HTTPRequestMethodKey.String(ctx.Ctx.Request.Method),
			semconv.HTTPRouteKey.String(ctx.Ctx.Request.URL.Path),
			semconv.URLFullKey.String(ctx.Ctx.Request.URL.String()),
			semconv.URLSchemeKey.String(ctx.Ctx.Request.URL.Scheme),
		}
		if ua := ctx.Ctx.Request.UserAgent(); ua != "" {
			attrs = append(attrs, semconv.UserAgentOriginalKey.String(ua))
		}
		if host := ctx.Ctx.Request.Host; host != "" {
			attrs = append(attrs, semconv.ServerAddressKey.String(host))
		}
		spanCtx, span := tracer.Start(ctxReq, spanName, trace.WithAttributes(attrs...), trace.WithSpanKind(trace.SpanKindServer))
		defer func() {
			status := ctx.Ctx.ResponseWriter.Status
			span.SetAttributes(
				semconv.HTTPResponseStatusCodeKey.Int(status),
				attribute.String("otel.debug", "http-root"),
			)
			span.SetStatus(httpStatusCodeToSpanStatus(status), http.StatusText(status))
			span.End()
		}()

		// Inject the span context into the request headers and Beego context
		propagator.Inject(spanCtx, carrier)
		ctx.Ctx.Request = ctx.Ctx.Request.WithContext(spanCtx)

		handler(ctx)
	}
}
