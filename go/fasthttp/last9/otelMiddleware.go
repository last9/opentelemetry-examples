package last9

import (
	"fmt"
	"net"
	"regexp"
	"strings"

	"github.com/valyala/fasthttp"
	"go.opentelemetry.io/otel/attribute"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

const (
	TracerKey = "otel-go-contrib-tracer"
	// ScopeName is the instrumentation scope name.
	ScopeName = "go.opentelemetry.io/contrib/instrumentation/github.com/valyala/fasthttp/otelfasthttp"
)

// Config represents the configuration for the middleware.
type Config struct {
	TracerProvider trace.TracerProvider
	Propagators    propagation.TextMapPropagator
	Filters        []Filter
}

// Filter is a function that filters requests for tracing.
type Filter func(*fasthttp.RequestCtx) bool

// Option is a function that can be used to configure the middleware.
type Option func(*Config)

// Middleware returns middleware that will trace incoming requests.
// The service parameter should describe the name of the (virtual)
// server handling the request.
func OtelMiddleware(service string) func(fasthttp.RequestHandler) fasthttp.RequestHandler {
	cfg := Config{}
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
	return func(next fasthttp.RequestHandler) fasthttp.RequestHandler {
		return func(ctx *fasthttp.RequestCtx) {
			for _, f := range cfg.Filters {
				if !f(ctx) {
					// Skip tracing if a filter rejects the request.
					next(ctx)
					return
				}
			}
			ctx.SetUserValue(TracerKey, tracer)
			carrier := fasthttpCarrier{ctx: ctx}
			propagatedCtx := cfg.Propagators.Extract(ctx, carrier)
			route := ctx.Path()
			opts := []trace.SpanStartOption{
				trace.WithAttributes(httpServerAttributes(service, ctx)...),
				trace.WithSpanKind(trace.SpanKindServer),
			}
			spanName := normalizePath(string(route))
			if spanName == "" {
				spanName = fmt.Sprintf("HTTP %s route not found", string(ctx.Method()))
			}
			spanCtx, span := tracer.Start(propagatedCtx, spanName, opts...)
			defer span.End()

			// Inject the span context back into the request headers
			cfg.Propagators.Inject(spanCtx, carrier)

			// Call the next handler
			next(ctx)

			status := ctx.Response.StatusCode()
			span.SetStatus(httpStatusCodeToSpanStatus(status))
			if status > 0 {
				span.SetAttributes(semconv.HTTPStatusCode(status))
			}
		}
	}
}

// httpServerAttributes returns a set of span attributes for HTTP server requests
func httpServerAttributes(service string, ctx *fasthttp.RequestCtx) []attribute.KeyValue {
	attrs := []attribute.KeyValue{
		semconv.ServiceNameKey.String(service),
		semconv.HTTPMethodKey.String(string(ctx.Method())),
		semconv.HTTPTargetKey.String(string(ctx.RequestURI())),
		semconv.HTTPURLKey.String(ctx.URI().String()),
		semconv.HTTPSchemeKey.String(string(ctx.URI().Scheme())),
	}

	if host := string(ctx.Host()); host != "" {
		attrs = append(attrs, semconv.ServerAddressKey.String(host))
	}

	if ua := string(ctx.UserAgent()); ua != "" {
		attrs = append(attrs, semconv.UserAgentOriginalKey.String(ua))
	}

	if ctx.RemoteIP() != nil {
		attrs = append(attrs, semconv.NetworkTypeIpv4.Key.String(ctx.RemoteIP().String()))
	}

	if remoteAddr, ok := ctx.RemoteAddr().(*net.TCPAddr); ok {
		attrs = append(attrs, semconv.NetSockPeerAddrKey.String(remoteAddr.IP.String()))
		attrs = append(attrs, semconv.NetSockPeerPortKey.Int(remoteAddr.Port))
	}

	// Add content length if available
	if length := ctx.Request.Header.ContentLength(); length >= 0 {
		attrs = append(attrs, semconv.HTTPRequestContentLengthKey.Int(length))
	}

	// Add user agent if available
	if userAgent := string(ctx.UserAgent()); userAgent != "" {
		attrs = append(attrs, semconv.UserAgentOriginalKey.String(userAgent))
	}

	return attrs
}

// fasthttpCarrier is a type that adapts fasthttp request to TextMapCarrier.
type fasthttpCarrier struct {
	ctx *fasthttp.RequestCtx
}

// Get returns the value associated with the passed key.
func (c fasthttpCarrier) Get(key string) string {
	return string(c.ctx.Request.Header.Peek(key))
}

// Set stores the key-value pair.
func (c fasthttpCarrier) Set(key string, value string) {
	c.ctx.Request.Header.Set(key, value)
}

// Keys lists the keys stored in this carrier.
func (c fasthttpCarrier) Keys() []string {
	var keys []string
	c.ctx.Request.Header.VisitAll(func(key, _ []byte) {
		keys = append(keys, string(key))
	})
	return keys
}

// httpStatusCodeToSpanStatus converts an HTTP status code to a span status.
func httpStatusCodeToSpanStatus(code int) (codes.Code, string) {
	if code < 100 || code >= 600 {
		return codes.Error, fmt.Sprintf("Invalid status code %d", code)
	}
	if code >= 400 {
		return codes.Error, fmt.Sprintf("HTTP status code: %d", code)
	}
	return codes.Ok, ""
}

// WithTracerProvider specifies a tracer provider to use for creating a tracer.
// If none is specified, the global provider is used.
func WithTracerProvider(provider trace.TracerProvider) Option {
	return func(cfg *Config) {
		cfg.TracerProvider = provider
	}
}

// WithPropagators specifies propagators to use for extracting
// information from the HTTP requests. If none are specified, global
// ones will be used.
func WithPropagators(propagators propagation.TextMapPropagator) Option {
	return func(cfg *Config) {
		cfg.Propagators = propagators
	}
}

// WithFilter adds a filter to the list of filters used by the middleware.
// If any filter indicates to exclude a request, the request will not be
// traced.
func WithFilter(f Filter) Option {
	return func(cfg *Config) {
		cfg.Filters = append(cfg.Filters, f)
	}
}

// SemVersion is the semantic version to be supplied to tracer creation.
func SemVersion() string {
	return "0.0.1"
}

func normalizePath(path string) string {
	// Replace UUIDs
	uuidRegex := regexp.MustCompile(`[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`)
	path = uuidRegex.ReplaceAllString(path, ":uuid")

	// Replace numeric IDs
	numericIDRegex := regexp.MustCompile(`/\d+(/|$)`)
	path = numericIDRegex.ReplaceAllString(path, "/:id$1")

	// Replace date patterns (YYYY-MM-DD)
	dateRegex := regexp.MustCompile(`/\d{4}-\d{2}-\d{2}(/|$)`)
	path = dateRegex.ReplaceAllString(path, "/:date$1")

	// Replace timestamps (Unix epoch)
	timestampRegex := regexp.MustCompile(`/\d{10,13}(/|$)`)
	path = timestampRegex.ReplaceAllString(path, "/:timestamp$1")

	// Replace GUIDs (without dashes)
	guidRegex := regexp.MustCompile(`/[0-9a-fA-F]{32}(/|$)`)
	path = guidRegex.ReplaceAllString(path, "/:guid$1")

	// Replace language codes (e.g., en-US, fr, de-DE)
	langRegex := regexp.MustCompile(`/[a-z]{2}(-[A-Z]{2})?(/|$)`)
	path = langRegex.ReplaceAllString(path, "/:lang$1")

	// Remove trailing slash if present
	path = strings.TrimSuffix(path, "/")

	return path
}
