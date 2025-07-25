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
    // Cache for performance optimization
    private static $requestCount = 0;
    private static $lastResetTime = 0;
    
    public function handle($request, Closure $next)
    {
        $tracer = $GLOBALS['otel_tracer'] ?? null;
        if (!$tracer) {
            return $next($request);
        }

        // Create root span for HTTP server request with minimal attributes
        $spanBuilder = $tracer->spanBuilder($this->generateSpanName($request))
            ->setSpanKind(SpanKind::KIND_SERVER);
        
        // Add only essential HTTP server attributes to reduce overhead
        $spanBuilder->setAttribute(TraceAttributes::HTTP_METHOD, $request->method())
                   ->setAttribute(TraceAttributes::HTTP_SCHEME, $request->getScheme())
                   ->setAttribute('url.path', $request->path())
                   ->setAttribute(TraceAttributes::HTTP_HOST, $request->getHost());
        
        // Add optional attributes only if they exist and are needed
        $userAgent = $request->userAgent();
        if ($userAgent) {
            $spanBuilder->setAttribute(TraceAttributes::HTTP_USER_AGENT, $userAgent);
        }
        
        $clientIp = $request->ip();
        if ($clientIp) {
            $spanBuilder->setAttribute('client.address', $clientIp);
        }
        
        $span = $spanBuilder->startSpan();
        $scope = $span->activate();

        try {
            $response = $next($request);
            
            // Set response status code
            $span->setAttribute(TraceAttributes::HTTP_STATUS_CODE, $response->getStatusCode());
            
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
            // Set error status with minimal overhead
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            $span->end();
            $scope->detach();
            
            throw $e;
        }
    }

    // Generate span name with minimal overhead
    private function generateSpanName($request)
    {
        // Use route name if available, otherwise use method + path
        $route = $request->route();
        if ($route && $route->getName()) {
            return $route->getName();
        }
        
        return $request->method() . ' ' . $request->path();
    }
    
    // Conditional tracing logic to reduce overhead (not currently used)
    private function conditionalTrace($request)
    {
        // Always trace error responses and slow requests
        if ($request->isMethod('POST') || $request->isMethod('PUT') || $request->isMethod('DELETE')) {
            return true; // Trace all mutations
        }
        
        // For GET requests, use adaptive sampling based on request rate
        $currentTime = time();
        
        // Reset counter every minute
        if ($currentTime - self::$lastResetTime > 60) {
            self::$requestCount = 0;
            self::$lastResetTime = $currentTime;
        }
        
        self::$requestCount++;
        
        // Sample GET requests based on rate:
        // - If < 100 requests/min: trace 100%
        // - If 100-500 requests/min: trace 50%
        // - If 500-1000 requests/min: trace 25%
        // - If > 1000 requests/min: trace 10%
        
        if (self::$requestCount <= 100) {
            return true; // Trace all requests when traffic is low
        } elseif (self::$requestCount <= 500) {
            return (self::$requestCount % 2) === 0; // 50% sampling
        } elseif (self::$requestCount <= 1000) {
            return (self::$requestCount % 4) === 0; // 25% sampling
        } else {
            return (self::$requestCount % 10) === 0; // 10% sampling
        }
    }
}