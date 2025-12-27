"""
Sanic application demonstrating event loop diagnostics with OpenTelemetry.

This application showcases:
1. Custom event loop monitoring with OTEL metrics
2. Various blocking vs non-blocking patterns
3. How to identify event loop problems through metrics

Endpoints demonstrate both GOOD (non-blocking) and BAD (blocking) patterns
so you can see how they affect event loop metrics.
"""

import asyncio
import time
import hashlib
import os
from concurrent.futures import ThreadPoolExecutor
from functools import partial

from sanic import Sanic, response
from sanic.request import Request
from opentelemetry import trace, context
from opentelemetry.propagate import extract
from opentelemetry.trace import SpanKind, Status, StatusCode

from otel_setup import setup_opentelemetry, shutdown_opentelemetry
from event_loop_monitor import EventLoopMonitor


# Create Sanic application
app = Sanic("event-loop-diagnostics")

# Global references (initialized on server start)
event_loop_monitor: EventLoopMonitor = None
tracer = None
meter = None

# Thread pool for offloading CPU-bound work
thread_pool = ThreadPoolExecutor(max_workers=4)


# ============================================
# INITIALIZATION
# ============================================

@app.before_server_start
async def setup_otel_and_monitor(app, loop):
    """Initialize OpenTelemetry and event loop monitor when server starts."""
    global tracer, meter, event_loop_monitor

    service_name = os.getenv("OTEL_SERVICE_NAME", "sanic-event-loop-demo")

    # Setup OpenTelemetry (tracing + metrics)
    tracer, meter = setup_opentelemetry(service_name=service_name)

    # Create and start our custom event loop monitor
    event_loop_monitor = EventLoopMonitor(
        meter=meter,
        interval=0.1,  # Check every 100ms
        blocking_threshold=0.05,  # 50ms = blocking warning
        critical_threshold=0.5,  # 500ms = critical
        service_name=service_name
    )
    await event_loop_monitor.start()

    print(f"Event loop monitor started for {service_name}")
    print(f"  - Monitoring interval: 100ms")
    print(f"  - Blocking threshold: 50ms")
    print(f"  - Critical threshold: 500ms")


@app.after_server_stop
async def cleanup(app, loop):
    """Cleanup on server shutdown."""
    global event_loop_monitor

    if event_loop_monitor:
        await event_loop_monitor.stop()

    shutdown_opentelemetry()
    thread_pool.shutdown(wait=True)


# ============================================
# OPENTELEMETRY MIDDLEWARE
# ============================================

@app.middleware("request")
async def otel_request_middleware(request: Request):
    """Create span for incoming requests with trace context propagation."""
    ctx = extract(request.headers)

    span = tracer.start_span(
        f"{request.method} {request.path}",
        context=ctx,
        kind=SpanKind.SERVER
    )

    span.set_attribute("http.method", request.method)
    span.set_attribute("http.url", str(request.url))
    span.set_attribute("http.target", request.path)

    token = context.attach(ctx)
    ctx_with_span = trace.set_span_in_context(span, ctx)
    token_span = context.attach(ctx_with_span)

    request.ctx.otel_span = span
    request.ctx.otel_token = token
    request.ctx.otel_token_span = token_span


@app.middleware("response")
async def otel_response_middleware(request: Request, response_obj):
    """End span on response."""
    if not hasattr(request.ctx, 'otel_span'):
        return

    span = request.ctx.otel_span

    if response_obj:
        span.set_attribute("http.status_code", response_obj.status)
        if response_obj.status >= 400:
            span.set_status(Status(StatusCode.ERROR))

    span.end()

    if hasattr(request.ctx, 'otel_token_span'):
        context.detach(request.ctx.otel_token_span)
    if hasattr(request.ctx, 'otel_token'):
        context.detach(request.ctx.otel_token)


# ============================================
# BASIC ENDPOINTS
# ============================================

@app.route("/")
async def index(request: Request):
    """Index page with endpoint documentation."""
    return response.json({
        "service": "Event Loop Diagnostics Demo",
        "description": "Demonstrates event loop monitoring with OpenTelemetry",
        "endpoints": {
            "monitoring": {
                "/health": "Health check",
                "/metrics": "Current event loop metrics (JSON)",
                "/metrics/reset": "Reset metrics counters"
            },
            "non_blocking_patterns": {
                "/async-io": "Async I/O operation (non-blocking)",
                "/proper-cpu?iterations=N": "CPU work offloaded to thread pool (non-blocking)",
                "/concurrent-tasks?count=N": "Run N concurrent async tasks"
            },
            "blocking_patterns_bad": {
                "/blocking-io?seconds=N": "time.sleep() - BLOCKS event loop",
                "/cpu-bound?iterations=N": "CPU work in main loop - BLOCKS event loop",
                "/blocking-hash?size=N": "Large hash computation - BLOCKS event loop"
            },
            "stress_testing": {
                "/stress-test?requests=N&concurrent=M": "Generate load to test monitoring"
            }
        },
        "tips": [
            "Watch /metrics while calling blocking endpoints",
            "Compare lag_ms between blocking and non-blocking calls",
            "blocking_events_total counts detected blocking operations"
        ]
    })


@app.route("/health")
async def health(request: Request):
    """Health check endpoint."""
    stats = event_loop_monitor.get_stats() if event_loop_monitor else {}
    return response.json({
        "status": "healthy",
        "event_loop_status": stats.get("status", "unknown"),
        "lag_ms": stats.get("lag_ms", 0)
    })


@app.route("/metrics")
async def metrics_endpoint(request: Request):
    """Return current event loop metrics."""
    if not event_loop_monitor:
        return response.json({"error": "Monitor not initialized"}, status=500)

    return response.json(event_loop_monitor.get_stats())


@app.route("/metrics/reset")
async def reset_metrics(request: Request):
    """Reset event loop metrics counters."""
    if event_loop_monitor:
        event_loop_monitor.reset_stats()
    return response.json({"message": "Metrics reset"})


# ============================================
# NON-BLOCKING PATTERNS (GOOD)
# ============================================

@app.route("/async-io")
async def async_io(request: Request):
    """
    Demonstrates proper async I/O - does NOT block event loop.

    asyncio.sleep() yields control back to the event loop,
    allowing other tasks to run while "waiting".
    """
    with tracer.start_as_current_span("async_io_operation") as span:
        span.set_attribute("operation.type", "async_io")

        # Simulate async I/O (e.g., database query, HTTP request)
        await asyncio.sleep(0.1)  # 100ms async wait

        return response.json({
            "pattern": "async_io",
            "blocking": False,
            "description": "asyncio.sleep() yields to event loop - other tasks can run",
            "simulated_wait_ms": 100
        })


@app.route("/proper-cpu")
async def proper_cpu(request: Request):
    """
    Demonstrates proper handling of CPU-bound work - does NOT block event loop.

    CPU-intensive work is offloaded to a thread pool using run_in_executor(),
    which prevents blocking the event loop.
    """
    iterations = int(request.args.get("iterations", 1000000))

    with tracer.start_as_current_span("proper_cpu_operation") as span:
        span.set_attribute("operation.type", "cpu_offloaded")
        span.set_attribute("iterations", iterations)

        # Offload CPU work to thread pool
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(
            thread_pool,
            partial(cpu_intensive_work, iterations)
        )

        return response.json({
            "pattern": "cpu_offloaded",
            "blocking": False,
            "description": "CPU work offloaded to thread pool via run_in_executor()",
            "iterations": iterations,
            "result": result
        })


@app.route("/concurrent-tasks")
async def concurrent_tasks(request: Request):
    """
    Demonstrates running multiple concurrent async tasks.

    All tasks run concurrently in the same event loop.
    Good for parallel I/O operations.
    """
    count = int(request.args.get("count", 5))

    with tracer.start_as_current_span("concurrent_tasks") as span:
        span.set_attribute("task.count", count)

        async def async_task(task_id: int):
            await asyncio.sleep(0.05)  # 50ms each
            return f"Task {task_id} complete"

        # Run all tasks concurrently
        tasks = [async_task(i) for i in range(count)]
        results = await asyncio.gather(*tasks)

        return response.json({
            "pattern": "concurrent_tasks",
            "blocking": False,
            "description": "Multiple tasks running concurrently via asyncio.gather()",
            "task_count": count,
            "results": results
        })


# ============================================
# BLOCKING PATTERNS (BAD - FOR DEMONSTRATION)
# ============================================

@app.route("/blocking-io")
async def blocking_io(request: Request):
    """
    INTENTIONALLY BLOCKS the event loop using time.sleep().

    This is a BAD pattern - time.sleep() blocks the entire thread,
    preventing the event loop from processing other tasks.

    Watch the /metrics endpoint - lag will spike!
    """
    seconds = float(request.args.get("seconds", 0.5))

    with tracer.start_as_current_span("blocking_io_operation") as span:
        span.set_attribute("operation.type", "blocking_io")
        span.set_attribute("blocking.duration_seconds", seconds)
        span.set_attribute("blocking.intentional", True)

        # BAD: This blocks the event loop!
        time.sleep(seconds)

        return response.json({
            "pattern": "blocking_io",
            "blocking": True,
            "warning": "time.sleep() blocks the event loop!",
            "description": "Use asyncio.sleep() instead for async code",
            "blocked_for_seconds": seconds
        })


@app.route("/cpu-bound")
async def cpu_bound(request: Request):
    """
    INTENTIONALLY BLOCKS the event loop with CPU-intensive work.

    This is a BAD pattern - long-running CPU work prevents the
    event loop from processing other tasks.

    Watch the /metrics endpoint - lag will spike!
    """
    iterations = int(request.args.get("iterations", 10000000))

    with tracer.start_as_current_span("cpu_bound_operation") as span:
        span.set_attribute("operation.type", "cpu_bound")
        span.set_attribute("iterations", iterations)
        span.set_attribute("blocking.intentional", True)

        # BAD: This blocks the event loop!
        result = cpu_intensive_work(iterations)

        return response.json({
            "pattern": "cpu_bound",
            "blocking": True,
            "warning": "CPU-intensive work blocks the event loop!",
            "description": "Use run_in_executor() to offload to thread pool",
            "iterations": iterations,
            "result": result
        })


@app.route("/blocking-hash")
async def blocking_hash(request: Request):
    """
    INTENTIONALLY BLOCKS the event loop with hash computation.

    Real-world example: password hashing, file checksums, etc.
    """
    size_mb = int(request.args.get("size", 10))

    with tracer.start_as_current_span("blocking_hash_operation") as span:
        span.set_attribute("operation.type", "blocking_hash")
        span.set_attribute("data_size_mb", size_mb)
        span.set_attribute("blocking.intentional", True)

        # BAD: This blocks the event loop!
        data = b"x" * (size_mb * 1024 * 1024)
        hash_result = hashlib.sha256(data).hexdigest()

        return response.json({
            "pattern": "blocking_hash",
            "blocking": True,
            "warning": "Large hash computation blocks the event loop!",
            "description": "Offload to thread pool for large data",
            "data_size_mb": size_mb,
            "hash": hash_result[:16] + "..."
        })


# ============================================
# STRESS TESTING
# ============================================

@app.route("/stress-test")
async def stress_test(request: Request):
    """
    Generate load to test event loop monitoring.

    Spawns multiple concurrent requests internally.
    """
    num_requests = int(request.args.get("requests", 10))
    concurrent = int(request.args.get("concurrent", 5))
    include_blocking = request.args.get("blocking", "false").lower() == "true"

    with tracer.start_as_current_span("stress_test") as span:
        span.set_attribute("test.requests", num_requests)
        span.set_attribute("test.concurrent", concurrent)
        span.set_attribute("test.include_blocking", include_blocking)

        async def simulated_request(i: int):
            if include_blocking and i % 3 == 0:
                # Every 3rd request is blocking
                time.sleep(0.1)
            else:
                await asyncio.sleep(0.05)
            return i

        # Process in batches
        results = []
        for batch_start in range(0, num_requests, concurrent):
            batch = [
                simulated_request(i)
                for i in range(batch_start, min(batch_start + concurrent, num_requests))
            ]
            batch_results = await asyncio.gather(*batch)
            results.extend(batch_results)

        stats = event_loop_monitor.get_stats() if event_loop_monitor else {}

        return response.json({
            "completed_requests": len(results),
            "concurrent": concurrent,
            "included_blocking": include_blocking,
            "event_loop_stats": stats
        })


# ============================================
# HELPER FUNCTIONS
# ============================================

def cpu_intensive_work(iterations: int) -> str:
    """CPU-intensive work for demonstration."""
    total = 0
    for i in range(iterations):
        total += i * i
    return f"sum_of_squares({iterations}) = {total}"


# ============================================
# MAIN
# ============================================

if __name__ == "__main__":
    # For development - use environment variables for configuration
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", 8000))
    debug = os.getenv("DEBUG", "true").lower() == "true"

    print(f"\nStarting Event Loop Diagnostics Demo")
    print(f"====================================")
    print(f"Server: http://{host}:{port}")
    print(f"Debug: {debug}")
    print(f"\nEndpoints to try:")
    print(f"  GET /metrics           - View event loop stats")
    print(f"  GET /async-io          - Non-blocking async I/O")
    print(f"  GET /blocking-io       - BLOCKS the event loop")
    print(f"  GET /cpu-bound         - BLOCKS with CPU work")
    print(f"  GET /proper-cpu        - CPU work done correctly")
    print(f"\nWatch /metrics while calling blocking endpoints!\n")

    app.run(host=host, port=port, debug=debug, auto_reload=debug)
