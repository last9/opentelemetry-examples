<?php

namespace App\Http\Middleware;

use Closure;
use Exception;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\Context\Context;

class OpenTelemetryMiddleware
{
    public function handle($request, Closure $next)
    {
        $tracer = $GLOBALS['official_tracer'] ?? null;
        if (!$tracer) {
            return $next($request);
        }

        // Create root span for this HTTP request
        $span = $tracer->spanBuilder($this->generateSpanName($request))
            ->setSpanKind(SpanKind::KIND_SERVER)
            ->setAttribute('http.request.method', $request->method())
            ->setAttribute('url.scheme', $request->getScheme())
            ->setAttribute('url.path', $request->path())
            ->setAttribute('server.address', $request->getHost())
            ->setAttribute('server.port', $request->getPort())
            ->setAttribute('user_agent.original', $request->userAgent())
            ->setAttribute('client.address', $request->ip())
            ->setAttribute('network.protocol.version', $request->getProtocolVersion())
            ->setAttribute('http.route', $request->route() ? $request->route()->getName() : '')
            ->setAttribute('url.query', $this->sanitizeQueryString($request->getQueryString()))
            ->setAttribute('url.full', $this->buildUrl($request))
            ->setAttribute('http.request.body.size', $request->header('content-length', 0))
            ->startSpan();

        // Set this span as the current span for context propagation
        $scope = $span->activate();
        
        // Store the scope in globals so we can close it later
        $GLOBALS['current_span_scope'] = $scope;

        try {
            $response = $next($request);
            
            // Set response attributes
            $span->setAttribute('http.response.status_code', $response->getStatusCode());
            $span->setAttribute('http.response.body.size', strlen($response->getContent()));
            
            // Set span status based on response
            if ($response->getStatusCode() >= 400) {
                $span->setStatus(StatusCode::STATUS_ERROR, 'HTTP ' . $response->getStatusCode());
            } else {
                $span->setStatus(StatusCode::STATUS_OK);
            }
            
            $span->end();
            $scope->detach();
            
            return $response;
            
        } catch (Exception $e) {
            // Set error attributes
            $span->setAttribute('exception.type', get_class($e));
            $span->setAttribute('exception.message', $e->getMessage());
            $span->setAttribute('exception.stacktrace', $e->getTraceAsString());
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->recordException($e);
            
            $span->end();
            $scope->detach();
            
            throw $e;
        }
    }

    private function generateSpanName($request)
    {
        $method = $request->method();
        $path = $request->path();
        
        // Generate a meaningful span name
        if ($request->route() && $request->route()->getName()) {
            return $request->route()->getName();
        }
        
        return $method . ' ' . $path;
    }

    private function sanitizeQueryString($queryString)
    {
        if (!$queryString) {
            return '';
        }
        
        // Remove sensitive parameters
        $params = [];
        parse_str($queryString, $params);
        
        $sensitiveKeys = ['password', 'token', 'key', 'secret', 'auth'];
        foreach ($sensitiveKeys as $key) {
            if (isset($params[$key])) {
                $params[$key] = '[REDACTED]';
            }
        }
        
        return http_build_query($params);
    }

    private function buildUrl($request)
    {
        $url = $request->getScheme() . '://' . $request->getHost();
        
        if ($request->getPort() && $request->getPort() != 80 && $request->getPort() != 443) {
            $url .= ':' . $request->getPort();
        }
        
        $url .= $request->getRequestUri();
        
        return $this->sanitizeUrl($url);
    }

    private function sanitizeUrl($url)
    {
        // Remove sensitive information from URL
        $url = preg_replace('/\/\/[^:]+:[^@]+@/', '//***:***@', $url);
        return $url;
    }
}