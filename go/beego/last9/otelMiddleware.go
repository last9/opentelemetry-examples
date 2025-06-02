package last9

import (
	"net/http"
	"strings"

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
		defer span.End()

		// Inject the span context into the request headers
		propagator.Inject(spanCtx, carrier)

		ctx.Request = ctx.Request.WithContext(spanCtx)
		ctx.Input.SetData("otel-span", span)

		status := ctx.ResponseWriter.Status
		span.SetStatus(httpStatusCodeToSpanStatus(status), http.StatusText(status))
		span.SetAttributes(semconv.HTTPResponseStatusCodeKey.Int(status))
		return
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
