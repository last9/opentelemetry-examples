<?php

namespace App\Http\Middleware;

use Closure;
use Exception;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\Context\Context;
use OpenTelemetry\SemConv\TraceAttributes;

class OpenTelemetryMiddleware
{
    // Configurable route patterns to trace
    private $tracedRoutePatterns;
    
    public function __construct()
    {
        // Load traced route patterns from config
        $this->tracedRoutePatterns = config('otel.traced_routes');
    }
    
    public function handle($request, Closure $next)
    {
        // Only trace configured routes
        if (!$this->shouldTrace($request)) {
            return $next($request);
        }

        $tracer = $GLOBALS['otel_tracer'] ?? null;
        if (!$tracer) {
            return $next($request);
        }

        // Create root span for HTTP server request using official SDK semantic conventions
        $spanBuilder = $tracer->spanBuilder($this->generateSpanName($request))
            ->setSpanKind(SpanKind::KIND_SERVER);

        // Add essential HTTP server attributes following semantic conventions
        $attributes = [
            TraceAttributes::HTTP_METHOD => $request->method(),
            TraceAttributes::HTTP_SCHEME => $request->getScheme(),
            'url.path' => $request->path(),
            TraceAttributes::HTTP_HOST => $request->getHost(),
            'server.port' => $request->getPort(),
            TraceAttributes::HTTP_USER_AGENT => $request->userAgent(),
            'user_agent.original' => $request->header('User-Agent'),
            'client.address' => $request->ip(),
            'network.protocol.version' => $request->getProtocolVersion(),
        ];

        // Add optional attributes only if they exist
        if ($request->route() && $request->route()->getName()) {
            $attributes['http.route'] = $request->route()->getName();
        }

        // Add query string without sanitization (no regex overhead)
        if ($request->getQueryString()) {
            $attributes['url.query'] = $request->getQueryString();
        }

        // Add content length if available
        $contentLength = $request->header('content-length');
        if ($contentLength) {
            $attributes['http.request.body.size'] = (int)$contentLength;
        }

        // Add all attributes to span builder
        foreach ($attributes as $key => $value) {
            $spanBuilder->setAttribute($key, $value);
        }
        
        $span = $spanBuilder->startSpan();

        // Set this span as the current span for context propagation
        $scope = $span->activate();

        try {
            $response = $next($request);

            // Set response attributes using semantic conventions
            $span->setAttribute(TraceAttributes::HTTP_STATUS_CODE, $response->getStatusCode());

            // Only calculate response size if it's reasonable (avoid memory issues with large responses)
            $content = $response->getContent();
            if (strlen($content) < 1024 * 1024) { // Only for responses < 1MB
                $span->setAttribute('http.response.body.size', strlen($content));
            }

            // Set span status based on HTTP response status code
            if ($response->getStatusCode() >= 400) {
                $span->setStatus(StatusCode::STATUS_ERROR, 'HTTP ' . $response->getStatusCode());
            } else {
                $span->setStatus(StatusCode::STATUS_OK);
            }
            
            $span->end();
            $scope->detach();
            
            return $response;

        } catch (Exception $e) {
            // Set error attributes using semantic conventions
            $span->setAttribute('exception.type', get_class($e));
            $span->setAttribute('exception.message', $e->getMessage());
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);

            $span->end();
            $scope->detach();
            
            throw $e;
        }
    }

    // Generate span name with optimized performance
    private function generateSpanName($request)
    {
        // Use route name if available, otherwise use method + path
        $route = $request->route();
        if ($route && ($name = $route->getName())) {
            return $name;
        }
        
        return $request->method() . ' ' . $request->path();
    }

    // Check if request should be traced based on configured patterns
    private function shouldTrace($request)
    {
        $path = $request->path();
        
        // Check if path matches any of the configured patterns
        foreach ($this->tracedRoutePatterns as $pattern) {
            if (strpos($path, $pattern) === 0) {
                return true;
            }
        }
        
        return false;
    }
    
}