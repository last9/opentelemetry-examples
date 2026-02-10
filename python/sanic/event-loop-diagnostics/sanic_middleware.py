"""
Sanic Middleware for Event Loop Diagnostics
Instruments HTTP requests with event loop metrics and enriches OTEL traces
"""
import time
from typing import Optional

from sanic import Request, HTTPResponse
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

from event_loop_diagnostics import EventLoopDiagnostics


class EventLoopMiddleware:
    """
    Sanic middleware that tracks event loop metrics per request
    and enriches OTEL traces with event loop attributes
    """

    def __init__(self, diagnostics: EventLoopDiagnostics):
        """
        Initialize middleware

        Args:
            diagnostics: EventLoopDiagnostics instance
        """
        self.diagnostics = diagnostics

    async def before_request(self, request: Request):
        """
        Called before request processing

        Tracks when request enters the event loop
        """
        # Record when request enters the system
        request.ctx.request_start = time.perf_counter()
        request.ctx.loop_entry_lag = self.diagnostics.get_current_state().lag_ms

        # Get the OTEL span (created by manual instrumentation)
        span = getattr(request.ctx, "span", None)
        if span and span.is_recording():
            # Add event loop state at request start
            span.set_attribute("event_loop.lag_at_start_ms", request.ctx.loop_entry_lag)
            span.set_attribute(
                "event_loop.active_tasks_at_start",
                self.diagnostics.get_current_state().active_tasks
            )

    async def after_request(self, request: Request, response: HTTPResponse):
        """
        Called after request processing

        Calculates wait time and execution time, records metrics,
        and enriches OTEL span with event loop data
        """
        # Calculate timings
        request_end = time.perf_counter()
        total_time_ms = (request_end - request.ctx.request_start) * 1000

        # Estimate wait time vs execution time
        # In a real scenario, wait time is time spent in queue before handler execution
        # For simplicity, we'll use a heuristic based on lag
        current_lag = self.diagnostics.get_current_state().lag_ms
        estimated_wait_ms = (request.ctx.loop_entry_lag + current_lag) / 2
        estimated_execution_ms = total_time_ms - estimated_wait_ms

        # Ensure non-negative values
        estimated_wait_ms = max(0, estimated_wait_ms)
        estimated_execution_ms = max(0, estimated_execution_ms)

        # Get endpoint path
        endpoint = request.path

        # Record metrics to OTEL
        self.diagnostics.record_request_metrics(
            wait_time_ms=estimated_wait_ms,
            execution_time_ms=estimated_execution_ms,
            endpoint=endpoint,
            attributes={
                "http.method": request.method,
                "http.status_code": response.status
            }
        )

        # Enrich OTEL span with event loop attributes
        span = getattr(request.ctx, "span", None)
        if span and span.is_recording():
            span.set_attribute("event_loop.wait_ms", round(estimated_wait_ms, 2))
            span.set_attribute("event_loop.execution_ms", round(estimated_execution_ms, 2))
            span.set_attribute("event_loop.lag_at_end_ms", current_lag)
            span.set_attribute(
                "event_loop.active_tasks_at_end",
                self.diagnostics.get_current_state().active_tasks
            )

            # Mark if blocking was detected during this request
            if estimated_execution_ms > self.diagnostics.blocking_threshold_ms:
                span.set_attribute("event_loop.was_blocked", True)
                span.add_event("blocking_operation_detected", {
                    "execution_time_ms": estimated_execution_ms,
                    "threshold_ms": self.diagnostics.blocking_threshold_ms
                })
            else:
                span.set_attribute("event_loop.was_blocked", False)


def setup_event_loop_middleware(app, diagnostics: EventLoopDiagnostics):
    """
    Setup event loop middleware on Sanic app

    Args:
        app: Sanic application instance
        diagnostics: EventLoopDiagnostics instance

    Usage:
        from sanic import Sanic
        from event_loop_diagnostics import EventLoopDiagnostics
        from sanic_middleware import setup_event_loop_middleware

        app = Sanic("my-app")
        diagnostics = EventLoopDiagnostics(service_name="my-service")

        setup_event_loop_middleware(app, diagnostics)
    """
    middleware = EventLoopMiddleware(diagnostics)

    # Register middleware
    @app.middleware("request")
    async def event_loop_request_middleware(request):
        await middleware.before_request(request)

    @app.middleware("response")
    async def event_loop_response_middleware(request, response):
        await middleware.after_request(request, response)

    # Start diagnostics monitor when app starts
    @app.before_server_start
    async def start_diagnostics(app, loop):
        await diagnostics.start()

    # Stop diagnostics monitor when app stops
    @app.after_server_stop
    async def stop_diagnostics(app, loop):
        await diagnostics.stop()

    print(f"[EventLoopMiddleware] Middleware setup complete for {app.name}")
