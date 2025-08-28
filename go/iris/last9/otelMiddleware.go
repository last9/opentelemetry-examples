package last9

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/kataras/iris/v12"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

const (
	TracerKey = "otel-go-contrib-tracer"
	ScopeName = "go.opentelemetry.io/contrib/instrumentation/github.com/kataras/iris/v12/oteliris"
)

type Config struct {
	TracerProvider trace.TracerProvider
	Propagators    propagation.TextMapPropagator
	Filters        []Filter
}

type Filter func(iris.Context) bool

type Option func(*Config)

func OtelMiddleware(service string, opts ...Option) iris.Handler {
	cfg := Config{}
	for _, opt := range opts {
		opt(&cfg)
	}

	if cfg.TracerProvider == nil {
		cfg.TracerProvider = otel.GetTracerProvider()
	}
	tracer := cfg.TracerProvider.Tracer(
		ScopeName,
		trace.WithInstrumentationVersion(SemVersion()),
	)
	if cfg.Propagators == nil {
		cfg.Propagators = otel.GetTextMapPropagator()
	}

	return func(ctx iris.Context) {
		for _, f := range cfg.Filters {
			if !f(ctx) {
				ctx.Next()
				return
			}
		}

		ctx.Values().Set(TracerKey, tracer)
		carrier := irisCarrier{ctx: ctx}
		propagatedCtx := cfg.Propagators.Extract(ctx.Request().Context(), carrier)
		route := ctx.Path()
		opts := []trace.SpanStartOption{
			trace.WithAttributes(httpServerAttributes(service, ctx)...),
			trace.WithSpanKind(trace.SpanKindServer),
		}
		spanName := normalizePath(route)
		if spanName == "" {
			spanName = fmt.Sprintf("HTTP %s route not found", ctx.Method())
		}
		spanCtx, span := tracer.Start(propagatedCtx, spanName, opts...)
		defer span.End()

		// Inject the span context back into the request headers
		cfg.Propagators.Inject(spanCtx, carrier)

		// Call the next handler
		ctx.Next()

		status := ctx.GetStatusCode()
		span.SetStatus(httpStatusCodeToSpanStatus(status))
		if status > 0 {
			span.SetAttributes(semconv.HTTPStatusCode(status))
		}
	}
}

func httpServerAttributes(service string, ctx iris.Context) []attribute.KeyValue {
	attrs := []attribute.KeyValue{
		semconv.ServiceNameKey.String(service),
		semconv.HTTPMethodKey.String(ctx.Method()),
		semconv.HTTPTargetKey.String(ctx.Path()),
		semconv.HTTPURLKey.String(ctx.Request().URL.String()),
		semconv.HTTPSchemeKey.String(ctx.Request().URL.Scheme),
	}

	if host := ctx.Host(); host != "" {
		attrs = append(attrs, semconv.ServerAddressKey.String(host))
	}

	if ua := ctx.GetHeader("User-Agent"); ua != "" {
		attrs = append(attrs, semconv.UserAgentOriginalKey.String(ua))
	}

	if remoteAddr := ctx.RemoteAddr(); remoteAddr != "" {
		attrs = append(attrs, semconv.ClientAddressKey.String(remoteAddr))
	}

	if contentLength := ctx.GetContentLength(); contentLength >= 0 {
		attrs = append(attrs, semconv.HTTPRequestContentLengthKey.Int64(contentLength))
	}

	return attrs
}

type irisCarrier struct {
	ctx iris.Context
}

func (c irisCarrier) Get(key string) string {
	return c.ctx.GetHeader(key)
}

func (c irisCarrier) Set(key string, value string) {
	c.ctx.Header(key, value)
}

func (c irisCarrier) Keys() []string {
	keys := make([]string, 0, len(c.ctx.Request().Header))
	for key := range c.ctx.Request().Header {
		keys = append(keys, key)
	}
	return keys
}

func httpStatusCodeToSpanStatus(code int) (codes.Code, string) {
	if code < 100 || code >= 600 {
		return codes.Error, fmt.Sprintf("Invalid status code %d", code)
	}
	if code >= 400 {
		return codes.Error, fmt.Sprintf("HTTP status code: %d", code)
	}
	return codes.Ok, ""
}

func WithTracerProvider(provider trace.TracerProvider) Option {
	return func(cfg *Config) {
		cfg.TracerProvider = provider
	}
}

func WithPropagators(propagators propagation.TextMapPropagator) Option {
	return func(cfg *Config) {
		cfg.Propagators = propagators
	}
}

func WithFilter(f Filter) Option {
	return func(cfg *Config) {
		cfg.Filters = append(cfg.Filters, f)
	}
}

func SemVersion() string {
	return "0.0.1"
}

func normalizePath(path string) string {
	uuidRegex := regexp.MustCompile(`[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`)
	path = uuidRegex.ReplaceAllString(path, ":uuid")

	numericIDRegex := regexp.MustCompile(`/\d+(/|$)`)
	path = numericIDRegex.ReplaceAllString(path, "/:id$1")

	dateRegex := regexp.MustCompile(`/\d{4}-\d{2}-\d{2}(/|$)`)
	path = dateRegex.ReplaceAllString(path, "/:date$1")

	timestampRegex := regexp.MustCompile(`/\d{10,13}(/|$)`)
	path = timestampRegex.ReplaceAllString(path, "/:timestamp$1")

	guidRegex := regexp.MustCompile(`/[0-9a-fA-F]{32}(/|$)`)
	path = guidRegex.ReplaceAllString(path, "/:guid$1")

	langRegex := regexp.MustCompile(`/[a-z]{2}(-[A-Z]{2})?(/|$)`)
	path = langRegex.ReplaceAllString(path, "/:lang$1")

	path = strings.TrimSuffix(path, "/")

	return path
}
