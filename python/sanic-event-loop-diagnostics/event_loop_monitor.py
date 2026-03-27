"""
Event Loop Monitor - Custom OpenTelemetry instrumentation for asyncio event loop diagnostics.

This module provides metrics that the standard opentelemetry-instrumentation-asyncio
does NOT provide:
- Event loop lag (delay between task scheduling and execution)
- Active task count
- Blocking detection
- Event loop utilization
- GC pause correlation (attribute lag spikes to garbage collection)
- Connection pool saturation (asyncpg, aiohttp, aioredis)

The standard OTEL asyncio instrumentation only tracks coroutine duration and count,
which tells you WHAT your coroutines are doing, but not HOW HEALTHY your event loop is.

Competitive context (as of March 2026):
- Datadog: event loop metrics for Node.js only, nothing for Python
- New Relic: per-transaction eventLoopWait, no global lag/utilization/task breakdown
- Dynatrace/Sentry: no event loop metrics for Python
- OTel asyncio instrumentation: coroutine duration/count only, no health metrics
This module fills all those gaps.
"""

import asyncio
import gc
import time
import traceback
import sys
from typing import Optional, Dict, Any, Callable, List
from dataclasses import dataclass, field
from opentelemetry.metrics import Meter, CallbackOptions, Observation


@dataclass
class EventLoopStats:
    """Current event loop statistics."""
    lag_ms: float = 0.0
    active_tasks: int = 0
    utilization_percent: float = 0.0
    blocking_events: int = 0
    max_lag_ms: float = 0.0
    total_measurements: int = 0
    # Per-coroutine active task counts (updated every monitoring interval)
    task_breakdown: Dict[str, int] = field(default_factory=dict)
    gc_collections_since_last: Dict[int, int] = field(default_factory=dict)
    gc_objects_collected_since_last: Dict[int, int] = field(default_factory=dict)
    gc_lag_correlation: bool = False


class EventLoopMonitor:
    """
    Monitors asyncio event loop health and exports metrics via OpenTelemetry.

    Uses the sleep-based lag detection technique:
    - Requests a sleep of N seconds
    - Measures actual time elapsed
    - Difference = event loop lag (time loop was busy/blocked)

    This is the same approach used by:
    - New Relic Python Agent
    - loopmon library
    - monitored-ioloop library
    """

    def __init__(
        self,
        meter: Meter,
        interval: float = 0.1,
        blocking_threshold: float = 0.05,
        critical_threshold: float = 0.5,
        service_name: str = "unknown",
        resource_attributes: Optional[Dict[str, str]] = None
    ):
        """
        Initialize the event loop monitor.

        Args:
            meter: OpenTelemetry Meter instance for creating metrics
            interval: How often to measure lag (seconds). Default 100ms.
                     Smaller = more accurate but more overhead.
            blocking_threshold: Lag above this is considered "blocking" (seconds).
                               Default 50ms - typical threshold for user-perceptible delay.
            critical_threshold: Lag above this is "critical" (seconds). Default 500ms.
            service_name: Service name for metric attributes.
            resource_attributes: Extra attributes to attach to every metric data
                point. When using Prometheus client export (or any pull-based
                exporter), OTel Resource attributes are NOT automatically
                propagated as metric labels — they only appear in the
                Resource descriptor.  Pass key infrastructure labels here
                (e.g. deployment.environment, k8s.pod.name) so they are
                included on every Observation / record call.
        """
        self._meter = meter
        self._interval = interval
        self._blocking_threshold = blocking_threshold
        self._critical_threshold = critical_threshold
        self._service_name = service_name
        self._base_attributes = {"service.name": service_name}
        if resource_attributes:
            self._base_attributes.update(resource_attributes)

        # Current stats (updated by monitoring task)
        self._stats = EventLoopStats()
        self._running = False
        self._monitor_task: Optional[asyncio.Task] = None

        # For utilization calculation
        self._busy_time = 0.0
        self._total_time = 0.0

        # Timestamps of the most recent detected blocking event.
        # _last_blocking_start: loop.time() at the START of the monitoring
        #   interval during which the block was detected. The block happened
        #   somewhere between this time and _last_blocking_end.
        # _last_blocking_end: loop.time() when the monitor woke up after the block.
        # Used by request middleware to check if a block occurred DURING a
        # specific request's execution window — avoids false positives on
        # requests that run immediately after a block finishes.
        self._last_blocking_start: float = 0.0
        self._last_blocking_end: float = 0.0
        self._last_blocking_lag_ms: float = 0.0

        # The start time of the CURRENT monitoring interval (updated at the
        # beginning of each loop iteration). Used by the response middleware
        # to detect if a block is happening right now (i.e., the current
        # interval started before the request but hasn't stamped _last_blocking_*
        # yet because the event loop was frozen during the request).
        self._current_interval_start: float = 0.0

        # Track the operation that caused blocking (set by report_blocking_operation)
        self._last_blocking_operation: str = "unknown"

        # Stack trace of the blocking operation (captured when lag > threshold)
        # Helps pinpoint the exact code causing the block
        self._last_blocking_stack_trace: str = ""

        # GC tracking — snapshot counts at last check to compute deltas
        self._last_gc_stats = self._snapshot_gc()

        # Connection pool registry — callers register pools for monitoring
        self._connection_pools: Dict[str, Any] = {}

        # Create OTEL metrics
        self._setup_metrics()

    def _setup_metrics(self):
        """Create OpenTelemetry metric instruments."""

        # Event loop lag - the key health indicator
        # Using observable gauge with callback for real-time values
        self._meter.create_observable_gauge(
            name="asyncio.eventloop.lag",
            callbacks=[self._observe_lag],
            description="Event loop lag - delay between task scheduling and execution",
            unit="ms"
        )

        # Active tasks gauge
        self._meter.create_observable_gauge(
            name="asyncio.eventloop.active_tasks",
            callbacks=[self._observe_active_tasks],
            description="Number of active asyncio tasks",
            unit="{tasks}"
        )

        # Event loop utilization (0-100%)
        self._meter.create_observable_gauge(
            name="asyncio.eventloop.utilization",
            callbacks=[self._observe_utilization],
            description="Event loop utilization percentage (0-100)",
            unit="%"
        )

        # Maximum lag seen (useful for alerting on worst case)
        self._meter.create_observable_gauge(
            name="asyncio.eventloop.max_lag",
            callbacks=[self._observe_max_lag],
            description="Maximum event loop lag observed since start",
            unit="ms"
        )

        # Blocking detection counter
        self._blocking_counter = self._meter.create_counter(
            name="asyncio.eventloop.blocking_events",
            description="Count of detected blocking operations (lag > threshold)",
            unit="{events}"
        )

        # Histogram for lag distribution (useful for percentile analysis)
        self._lag_histogram = self._meter.create_histogram(
            name="asyncio.eventloop.lag_distribution",
            description="Distribution of event loop lag measurements",
            unit="ms"
        )

        # Per-coroutine active task count - shows trends of which coroutines
        # are active over time (attribute: task.coroutine)
        self._meter.create_observable_gauge(
            name="asyncio.eventloop.task.active_count",
            callbacks=[self._observe_task_breakdown],
            description="Number of active tasks broken down by coroutine name",
            unit="{tasks}"
        )

        # Per-coroutine lag contribution - records lag attributed to each
        # coroutine type when lag exceeds threshold (attribute: task.coroutine)
        # Use this to answer: "which tasks are contributing to event loop lag?"
        self._task_lag_histogram = self._meter.create_histogram(
            name="asyncio.eventloop.task.lag_contribution",
            description="Event loop lag attributed by coroutine type (recorded when lag > threshold)",
            unit="ms"
        )

        # ── GC metrics ──────────────────────────────────────────
        self._gc_collections_counter = self._meter.create_counter(
            name="asyncio.gc.collections",
            description="Garbage collection runs by generation",
            unit="{collections}"
        )

        self._gc_collected_counter = self._meter.create_counter(
            name="asyncio.gc.objects_collected",
            description="Objects collected by the garbage collector, by generation",
            unit="{objects}"
        )

        self._gc_lag_correlation_counter = self._meter.create_counter(
            name="asyncio.gc.lag_correlated",
            description="Count of monitoring intervals where GC ran AND lag exceeded the blocking threshold",
            unit="{events}"
        )

        # ── Connection pool metrics ─────────────────────────────
        self._meter.create_observable_gauge(
            name="asyncio.pool.size",
            callbacks=[self._observe_pool_size],
            description="Total size of a connection pool (max connections)",
            unit="{connections}"
        )

        self._meter.create_observable_gauge(
            name="asyncio.pool.available",
            callbacks=[self._observe_pool_available],
            description="Number of available (idle) connections in a pool",
            unit="{connections}"
        )

        self._meter.create_observable_gauge(
            name="asyncio.pool.waiters",
            callbacks=[self._observe_pool_waiters],
            description="Number of coroutines waiting for a connection from the pool",
            unit="{waiters}"
        )

    def _observe_lag(self, options: CallbackOptions):
        """Callback for lag gauge."""
        yield Observation(
            self._stats.lag_ms,
            self._base_attributes
        )

    def _observe_active_tasks(self, options: CallbackOptions):
        """Callback for active tasks gauge."""
        yield Observation(
            self._stats.active_tasks,
            self._base_attributes
        )

    def _observe_utilization(self, options: CallbackOptions):
        """Callback for utilization gauge."""
        yield Observation(
            self._stats.utilization_percent,
            self._base_attributes
        )

    def _observe_max_lag(self, options: CallbackOptions):
        """Callback for max lag gauge."""
        yield Observation(
            self._stats.max_lag_ms,
            self._base_attributes
        )

    def _observe_task_breakdown(self, options: CallbackOptions):
        """
        Callback for per-coroutine active task count gauge.

        Yields one Observation per unique coroutine name currently active,
        with the coroutine name as the 'task.coroutine' attribute.
        This creates separate time-series per coroutine type, enabling
        trend analysis of which tasks are active over time.
        """
        for coro_name, count in self._stats.task_breakdown.items():
            yield Observation(
                count,
                {
                    **self._base_attributes,
                    "task.coroutine": coro_name,
                }
            )

    @staticmethod
    def _snapshot_gc() -> List[Dict[str, int]]:
        """Return per-generation GC counters from gc.get_stats().

        Each entry is ``{"collections": <int>, "collected": <int>}`` keyed by
        generation index.  We snapshot these so the monitor loop can compute
        deltas between iterations.
        """
        return [
            {"collections": s.get("collections", 0), "collected": s.get("collected", 0)}
            for s in gc.get_stats()
        ]

    def _observe_pool_size(self, options: CallbackOptions):
        """Callback for pool size gauge — yields one Observation per registered pool."""
        for name, pool in self._connection_pools.items():
            size = getattr(pool, "size", None) or getattr(pool, "maxsize", 0)
            yield Observation(
                size,
                {**self._base_attributes, "pool.name": name}
            )

    def _observe_pool_available(self, options: CallbackOptions):
        """Callback for pool available (idle) connections gauge."""
        for name, pool in self._connection_pools.items():
            available = getattr(pool, "freesize", None)
            if available is None:
                available = getattr(pool, "available", 0)
            yield Observation(
                available,
                {**self._base_attributes, "pool.name": name}
            )

    def _observe_pool_waiters(self, options: CallbackOptions):
        """Callback for pool waiters gauge — coroutines waiting for a connection."""
        for name, pool in self._connection_pools.items():
            # asyncpg: pool._queue.qsize() (internal)
            queue = getattr(pool, "_queue", None)
            if queue is not None and hasattr(queue, "qsize"):
                waiters = queue.qsize()
            else:
                waiters = getattr(pool, "wait_count", 0)
            yield Observation(
                waiters,
                {**self._base_attributes, "pool.name": name}
            )

    def register_pool(self, name: str, pool: Any) -> None:
        """Register a connection pool for monitoring.

        Stores the pool so that the observable gauge callbacks can read its
        size / available / waiters on every metric collection cycle.

        Compatible pool types:
        - ``asyncpg.Pool``   — size, freesize, _queue
        - ``aiohttp.TCPConnector`` — available / limit
        - ``aioredis.ConnectionPool`` — maxsize, available, wait_count
        """
        self._connection_pools[name] = pool

    async def start(self):
        """Start the monitoring task."""
        if self._running:
            return

        self._running = True
        self._monitor_task = asyncio.create_task(self._monitor_loop())

    async def stop(self):
        """Stop the monitoring task gracefully."""
        self._running = False
        if self._monitor_task:
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass

    async def _monitor_loop(self):
        """
        Main monitoring loop - measures event loop lag continuously.

        The technique:
        1. Record current time
        2. Sleep for a fixed interval
        3. Measure actual elapsed time
        4. Lag = actual - requested

        If the event loop is healthy, lag should be near zero.
        If something is blocking the loop, lag will spike.
        """
        loop = asyncio.get_running_loop()

        while self._running:
            try:
                # Record start time using high-precision loop time
                start = loop.time()

                # Expose current interval start so the response middleware can
                # detect a block that is "in-flight" (not yet stamped in
                # _last_blocking_start because the monitor hasn't woken up yet).
                self._current_interval_start = start

                # Sleep for the monitoring interval
                await asyncio.sleep(self._interval)

                # Measure actual elapsed time
                elapsed = loop.time() - start

                # Calculate lag (excess time beyond requested sleep)
                lag_seconds = max(0, elapsed - self._interval)
                lag_ms = lag_seconds * 1000  # Convert to milliseconds

                # Update statistics
                self._stats.lag_ms = lag_ms
                self._stats.total_measurements += 1

                # Track maximum lag
                if lag_ms > self._stats.max_lag_ms:
                    self._stats.max_lag_ms = lag_ms

                # Count active tasks and build per-coroutine breakdown
                all_tasks = asyncio.all_tasks()
                current_task = asyncio.current_task()
                active_tasks = [t for t in all_tasks if not t.done() and t is not current_task]
                self._stats.active_tasks = len(active_tasks)

                # Build per-coroutine task count for trend tracking
                task_breakdown: Dict[str, int] = {}
                for task in active_tasks:
                    coro = task.get_coro()
                    coro_name = (
                        getattr(coro, "__qualname__", None)
                        or getattr(coro, "__name__", None)
                        or "unknown"
                    )
                    task_breakdown[coro_name] = task_breakdown.get(coro_name, 0) + 1
                self._stats.task_breakdown = task_breakdown

                # Calculate utilization (simplified: lag/interval ratio)
                # High lag = high utilization (loop was busy)
                self._busy_time += lag_seconds
                self._total_time += self._interval
                if self._total_time > 0:
                    self._stats.utilization_percent = min(100, (self._busy_time / self._total_time) * 100)

                # ── GC delta tracking ──────────────────────────────
                current_gc = self._snapshot_gc()
                gc_ran = False
                for gen in range(len(current_gc)):
                    delta_collections = current_gc[gen]["collections"] - self._last_gc_stats[gen]["collections"]
                    delta_collected = current_gc[gen]["collected"] - self._last_gc_stats[gen]["collected"]

                    if delta_collections > 0:
                        gc_ran = True
                        self._gc_collections_counter.add(
                            delta_collections,
                            {**self._base_attributes, "gc.generation": str(gen)}
                        )
                        self._stats.gc_collections_since_last[gen] = delta_collections

                    if delta_collected > 0:
                        self._gc_collected_counter.add(
                            delta_collected,
                            {**self._base_attributes, "gc.generation": str(gen)}
                        )
                        self._stats.gc_objects_collected_since_last[gen] = delta_collected

                if gc_ran and lag_seconds > self._blocking_threshold:
                    self._gc_lag_correlation_counter.add(1, self._base_attributes)
                    self._stats.gc_lag_correlation = True
                else:
                    self._stats.gc_lag_correlation = False

                self._last_gc_stats = current_gc

                # Record lag in histogram for distribution analysis (in milliseconds)
                self._lag_histogram.record(
                    lag_ms,
                    self._base_attributes
                )

                # Detect blocking events and attribute lag to contributing tasks
                if lag_seconds > self._blocking_threshold:
                    self._stats.blocking_events += 1

                    # Determine severity
                    if lag_seconds > self._critical_threshold:
                        severity = "critical"
                    else:
                        severity = "warning"

                    # NOTE: We DO NOT emit the blocking counter here anymore.
                    # The middleware will report blocking events with accurate
                    # operation labels via report_blocking_operation().
                    # This avoids duplicate/incorrect attributions where innocent
                    # requests get blamed for blocking that happened before them.

                    # Record the interval [start, now] during which the block
                    # occurred. The block happened somewhere between 'start'
                    # (when we went to sleep) and 'loop.time()' (when we woke).
                    # The middleware checks if a request's execution window
                    # overlaps with [_last_blocking_start, _last_blocking_end].
                    self._last_blocking_start = start
                    self._last_blocking_end = loop.time()
                    self._last_blocking_lag_ms = lag_ms

                    # Capture stack traces of all active tasks to pinpoint blocking code
                    # This helps identify the exact line causing the block
                    stack_traces = []
                    for task in active_tasks:
                        try:
                            coro = task.get_coro()
                            coro_name = (
                                getattr(coro, "__qualname__", None)
                                or getattr(coro, "__name__", None)
                                or "unknown"
                            )
                            # Get the coroutine frame for stack extraction
                            frame = getattr(coro, "cr_frame", None) or getattr(coro, "gi_frame", None)
                            if frame:
                                # Extract stack trace from the frame
                                stack = traceback.format_stack(frame, limit=5)
                                stack_summary = ''.join(stack[-3:])  # Last 3 frames
                                stack_traces.append(f"{coro_name}:\n{stack_summary}")
                        except Exception:
                            # Ignore errors in stack trace capture
                            pass

                    self._last_blocking_stack_trace = "\n---\n".join(stack_traces[:3])  # Top 3 tasks

                    # Record lag contribution per coroutine that was active
                    # during this blocking event. If no tasks are identified,
                    # attribute the lag to an "unknown" contributor so the
                    # metric is still emitted.
                    contributing_tasks = task_breakdown if task_breakdown else {"unknown": 1}
                    for coro_name in contributing_tasks:
                        self._task_lag_histogram.record(
                            lag_ms,
                            {
                                **self._base_attributes,
                                "task.coroutine": coro_name,
                                "blocking.severity": severity,
                            }
                        )

            except asyncio.CancelledError:
                break
            except Exception as e:
                # Don't let monitoring errors crash the application
                # In production, you might want to log this
                pass

    def get_stats(self) -> Dict[str, Any]:
        """
        Get current event loop statistics as a dictionary.
        Useful for exposing via an HTTP endpoint.
        """
        return {
            "lag_ms": round(self._stats.lag_ms, 3),
            "lag_seconds": round(self._stats.lag_ms / 1000, 6),
            "active_tasks": self._stats.active_tasks,
            "utilization_percent": round(self._stats.utilization_percent, 2),
            "blocking_events_total": self._stats.blocking_events,
            "max_lag_ms": round(self._stats.max_lag_ms, 3),
            "max_lag_seconds": round(self._stats.max_lag_ms / 1000, 6),
            "total_measurements": self._stats.total_measurements,
            "monitoring_interval_ms": self._interval * 1000,
            "blocking_threshold_ms": self._blocking_threshold * 1000,
            "status": self._get_health_status(),
            # Per-coroutine breakdown: shows which tasks are active right now
            # and (via OTEL) which ones have been contributing to lag over time.
            "task_breakdown": dict(self._stats.task_breakdown),
            "gc_lag_correlated": self._stats.gc_lag_correlation,
            "gc_stats": [
                {"generation": i, **s}
                for i, s in enumerate(gc.get_stats())
            ],
            "connection_pools": {
                name: {
                    "size": getattr(pool, "size", None) or getattr(pool, "maxsize", 0),
                    "available": getattr(pool, "freesize", None)
                    if getattr(pool, "freesize", None) is not None
                    else getattr(pool, "available", 0),
                }
                for name, pool in self._connection_pools.items()
            },
        }

    def _get_health_status(self) -> str:
        """Determine event loop health status based on current lag."""
        lag_seconds = self._stats.lag_ms / 1000
        if lag_seconds < 0.01:  # < 10ms
            return "healthy"
        elif lag_seconds < self._blocking_threshold:
            return "ok"
        elif lag_seconds < self._critical_threshold:
            return "degraded"
        else:
            return "critical"

    def reset_stats(self):
        """Reset statistics (useful for testing)."""
        self._stats = EventLoopStats()
        self._busy_time = 0.0
        self._total_time = 0.0

    def report_blocking_operation(self, operation_name: str, lag_ms: float, severity: str):
        """
        Report a blocking operation detected by external code (e.g., middleware).

        This allows the application middleware to report which specific HTTP endpoint
        or operation caused the blocking, with accurate labels for observability.

        Args:
            operation_name: Name of the operation (e.g., "GET /blocking-io")
            lag_ms: Measured lag in milliseconds
            severity: "warning" or "critical"
        """
        self._blocking_counter.add(
            1,
            {
                **self._base_attributes,
                "blocking.severity": severity,
                "blocking.lag_ms": str(round(lag_ms, 3)),
                "operation": operation_name,
            }
        )
