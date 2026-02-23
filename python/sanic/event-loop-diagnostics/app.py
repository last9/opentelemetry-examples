"""
Sanic App with Event Loop Diagnostics - OTLP APS1 Export
"""
import asyncio
import time
import os
from sanic import Sanic
from sanic.response import json
from opentelemetry import trace

# Import OTLP OTEL configuration
from otel_config_production import setup_otel_for_otlp

# Event loop diagnostics imports
from event_loop_diagnostics import EventLoopDiagnostics
from sanic_middleware import setup_event_loop_middleware

# Initialize Sanic app
app = Sanic("sanic-eventloop-otlp")

# Setup OTEL with OTLP APS1
setup_otel_for_otlp()

# Setup manual tracing middleware
tracer = trace.get_tracer(__name__)

@app.middleware("request")
async def add_otel_trace(request):
    request.ctx.span = tracer.start_span(
        f"{request.method} {request.path}",
        kind=trace.SpanKind.SERVER
    )
    request.ctx.span.set_attribute("http.method", request.method)
    request.ctx.span.set_attribute("http.route", request.path)

@app.middleware("response")
async def finish_otel_trace(request, response):
    if hasattr(request.ctx, "span"):
        request.ctx.span.set_attribute("http.status_code", response.status)
        request.ctx.span.end()

# Initialize Event Loop Diagnostics
diagnostics = EventLoopDiagnostics(
    service_name="sanic-eventloop-otlp",
    check_interval_ms=100,
    blocking_threshold_ms=50,
    enabled=True
)

# Setup middleware
setup_event_loop_middleware(app, diagnostics)

# Routes
@app.route("/")
async def index(request):
    return json({"service": "sanic-eventloop-otlp", "status": "exporting_to_otlp_aps1"})

@app.route("/health")
async def health(request):
    state = diagnostics.get_current_state()
    return json({
        "status": "healthy",
        "event_loop": {
            "lag_ms": round(state.lag_ms, 2),
            "active_tasks": state.active_tasks,
            "max_lag_ms": round(state.max_lag_ms, 2),
            "utilization_percent": round(state.utilization_percent, 2),
            "blocking_events_total": state.blocking_events_total
        }
    })

@app.route("/fast")
async def fast_endpoint(request):
    return json({"message": "Fast response"})

@app.route("/slow")
async def slow_endpoint(request):
    await asyncio.sleep(0.5)
    return json({"message": "Slow but non-blocking"})

@app.route("/blocking")
async def blocking_endpoint(request):
    time.sleep(0.3)
    return json({"message": "Blocking response (BAD!)", "warning": "Blocks event loop"})

@app.route("/concurrent")
async def concurrent_endpoint(request):
    async def worker(task_id, delay):
        await asyncio.sleep(delay)
        return f"task_{task_id}"
    
    tasks = [worker(i, 0.1) for i in range(10)]
    results = await asyncio.gather(*tasks)
    return json({"message": "Concurrent tasks", "results": results})

# Error handler
@app.exception(Exception)
async def handle_exception(request, exception):
    span = getattr(request.ctx, "span", None)
    if span and span.is_recording():
        span.record_exception(exception)
        span.set_status(trace.Status(trace.StatusCode.ERROR))
    return json({"error": str(exception)}, status=500)

if __name__ == "__main__":
    print("\n" + "="*70)
    print("Sanic Event Loop Diagnostics - OTLP APS1 Export")
    print("="*70)
    print("\n🚀 Exporting to OTLP Asia Pacific South 1")
    print("📊 Service: sanic-eventloop-otlp")
    print("🌐 Server: http://localhost:8000")
    print("\nEndpoints:")
    print("  /          - Service info")
    print("  /health    - Event loop metrics")
    print("  /fast      - Fast endpoint")
    print("  /slow      - Slow async (non-blocking)")
    print("  /blocking  - Blocking (BAD!)")
    print("  /concurrent - Concurrent tasks")
    print("="*70 + "\n")
    
    app.run(host="0.0.0.0", port=8000, debug=False, access_log=True)
