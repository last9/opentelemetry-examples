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
    deployment_environment = os.getenv("DEPLOYMENT_ENVIRONMENT", "unknown")

    # Setup OpenTelemetry (tracing + metrics)
    tracer, meter = setup_opentelemetry(service_name=service_name)

    # Create and start our custom event loop monitor
    event_loop_monitor = EventLoopMonitor(
        meter=meter,
        interval=0.1,  # Check every 100ms
        blocking_threshold=0.05,  # 50ms = blocking warning
        critical_threshold=0.5,  # 500ms = critical
        service_name=service_name,
        deployment_environment=deployment_environment
    )
    await event_loop_monitor.start()

    print(f"Event loop monitor started for {service_name}")
    print(f"  - Deployment environment: {deployment_environment}")
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

    # Record the loop.time() at request start.
    # The response middleware checks if a blocking event timestamp falls
    # BETWEEN this start time and the response time — correctly pinpointing
    # which handler caused the block, not which handler ran after it.
    if event_loop_monitor:
        loop = asyncio.get_running_loop()
        request.ctx.request_start_loop_time = loop.time()
        request.ctx.lag_at_start_ms = event_loop_monitor.get_stats()["lag_ms"]


@app.middleware("response")
async def otel_response_middleware(request: Request, response_obj):
    """
    End span on response, enriching it with event loop lag attributes.

    These span attributes let you answer in Last9 / any trace backend:
      "Which HTTP routes were being served during high event loop lag?"

    Filter traces by:
      asyncio.eventloop.request_blocked = true
      asyncio.eventloop.lag_at_request_end_ms > 50
    Then group by http.target to find the worst offenders.
    """
    if not hasattr(request.ctx, 'otel_span'):
        return

    span = request.ctx.otel_span

    if response_obj:
        span.set_attribute("http.status_code", response_obj.status)
        if response_obj.status >= 400:
            span.set_status(Status(StatusCode.ERROR))

    # Enrich span with event loop blocking attribution for this request.
    #
    # KEY INSIGHT: We use loop.time() timestamps rather than lag values to
    # determine if a block happened DURING this request. This avoids the
    # false-positive problem where a request running immediately AFTER a
    # blocking call inherits the stale high-lag reading.
    #
    # How it works:
    #   1. Request middleware stamps request_start_loop_time = loop.time()
    #   2. When lag > threshold, monitor stamps _last_blocking_loop_time
    #   3. Here we check: did that blocking event fall between start and now?
    #   4. If yes → THIS handler caused the block (true positive)
    #   5. If no  → block happened before/after this request (not its fault)
    if event_loop_monitor and hasattr(request.ctx, 'request_start_loop_time'):
        loop = asyncio.get_running_loop()
        request_end_loop_time = loop.time()
        request_start_loop_time = request.ctx.request_start_loop_time
        stats = event_loop_monitor.get_stats()

        last_blocking_start = event_loop_monitor._last_blocking_start
        last_blocking_end = event_loop_monitor._last_blocking_end
        last_blocking_lag_ms = event_loop_monitor._last_blocking_lag_ms
        current_interval_start = event_loop_monitor._current_interval_start
        blocking_threshold = event_loop_monitor._blocking_threshold

        # Strategy: detect blocking via two complementary checks.
        #
        # CHECK 1 — Stamped block (previous requests):
        #   After a block, the monitor wakes and stamps _last_blocking_start/end.
        #   A request owns the block if its window overlaps [block_start, block_end].
        #   Two intervals overlap when: A_start <= B_end AND B_start <= A_end.
        stamped_block = (
            last_blocking_start > 0
            and request_start_loop_time <= last_blocking_end
            and last_blocking_start <= request_end_loop_time
        )

        # CHECK 2 — In-flight block (the current request IS the culprit):
        #   When time.sleep() runs inside THIS request, the event loop freezes.
        #   The monitor can't run during the freeze, so _last_blocking_start is
        #   still from a previous cycle. But _current_interval_start was set
        #   BEFORE the freeze. If the current monitoring interval started before
        #   this request AND the request took longer than (interval + threshold),
        #   then the loop was blocked during this request.
        request_duration = request_end_loop_time - request_start_loop_time
        interval_elapsed = request_end_loop_time - current_interval_start
        inflight_block = (
            current_interval_start > 0
            and current_interval_start <= request_end_loop_time
            and interval_elapsed > (event_loop_monitor._interval + blocking_threshold)
        )

        was_blocked = stamped_block or inflight_block
        # Use actual measured lag for in-flight blocks
        if inflight_block and not stamped_block:
            last_blocking_lag_ms = max(0, interval_elapsed - event_loop_monitor._interval) * 1000

        span.set_attribute("asyncio.eventloop.lag_at_request_start_ms", round(request.ctx.lag_at_start_ms, 2))
        span.set_attribute("asyncio.eventloop.lag_at_request_end_ms", round(stats["lag_ms"], 2))
        span.set_attribute("asyncio.eventloop.request_blocked", was_blocked)
        span.set_attribute("asyncio.eventloop.active_tasks", stats["active_tasks"])

        if was_blocked:
            span.set_attribute("asyncio.eventloop.blocking_lag_ms", round(last_blocking_lag_ms, 2))
            severity = "critical" if last_blocking_lag_ms > stats["blocking_threshold_ms"] * 10 else "warning"
            span.set_attribute("asyncio.eventloop.blocking_severity", severity)

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
                "/metrics/reset": "Reset metrics counters",
                "/task-trends": "Active tasks by coroutine + OTEL lag attribution metrics"
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


@app.route("/task-trends")
async def task_trends(request: Request):
    """
    Show which coroutines are currently active and their contribution to lag.

    Returns the live task breakdown by coroutine name.

    For historical trends of which tasks contributed to event loop lag,
    query the OTEL metric:
      asyncio.eventloop.task.lag_contribution (histogram, attribute: task.coroutine)
      asyncio.eventloop.task.active_count     (gauge,     attribute: task.coroutine)

    Example PromQL to find top lag contributors:
      topk(5, rate(asyncio_eventloop_task_lag_contribution_sum[5m])
               / rate(asyncio_eventloop_task_lag_contribution_count[5m]))
    """
    if not event_loop_monitor:
        return response.json({"error": "Monitor not initialized"}, status=500)

    stats = event_loop_monitor.get_stats()
    task_breakdown = stats.get("task_breakdown", {})

    # Sort by count descending so highest-activity coroutines appear first
    sorted_tasks = sorted(task_breakdown.items(), key=lambda x: x[1], reverse=True)

    return response.json({
        "active_tasks_total": stats["active_tasks"],
        "current_lag_ms": stats["lag_ms"],
        "status": stats["status"],
        "task_breakdown": [
            {"coroutine": name, "active_count": count}
            for name, count in sorted_tasks
        ],
        "otel_metrics": {
            "active_count_by_coroutine": "asyncio.eventloop.task.active_count (attr: task.coroutine)",
            "lag_contribution_by_coroutine": "asyncio.eventloop.task.lag_contribution (attr: task.coroutine)",
            "note": "Query these metrics in your observability backend to see trends over time"
        }
    })


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
