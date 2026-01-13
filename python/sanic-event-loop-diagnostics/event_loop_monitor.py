"""
Event Loop Monitor - Custom OpenTelemetry instrumentation for asyncio event loop diagnostics.

This module provides metrics that the standard opentelemetry-instrumentation-asyncio
does NOT provide:
- Event loop lag (delay between task scheduling and execution)
- Active task count
- Blocking detection
- Event loop utilization

The standard OTEL asyncio instrumentation only tracks coroutine duration and count,
which tells you WHAT your coroutines are doing, but not HOW HEALTHY your event loop is.
"""

import asyncio
import time
from typing import Optional, Dict, Any, Callable
from dataclasses import dataclass, field
from opentelemetry.metrics import Meter, CallbackOptions, Observation


@dataclass
class EventLoopStats:
    """Current event loop statistics."""
    lag_seconds: float = 0.0
    active_tasks: int = 0
    utilization_percent: float = 0.0
    blocking_events: int = 0
    max_lag_seconds: float = 0.0
    total_measurements: int = 0


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
        service_name: str = "unknown"
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
        """
        self._meter = meter
        self._interval = interval
        self._blocking_threshold = blocking_threshold
        self._critical_threshold = critical_threshold
        self._service_name = service_name

        # Current stats (updated by monitoring task)
        self._stats = EventLoopStats()
        self._running = False
        self._monitor_task: Optional[asyncio.Task] = None

        # For utilization calculation
        self._busy_time = 0.0
        self._total_time = 0.0

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
            unit="s"
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
            unit="s"
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
            unit="s"
        )

    def _observe_lag(self, options: CallbackOptions):
        """Callback for lag gauge."""
        yield Observation(
            self._stats.lag_seconds,
            {"service.name": self._service_name}
        )

    def _observe_active_tasks(self, options: CallbackOptions):
        """Callback for active tasks gauge."""
        yield Observation(
            self._stats.active_tasks,
            {"service.name": self._service_name}
        )

    def _observe_utilization(self, options: CallbackOptions):
        """Callback for utilization gauge."""
        yield Observation(
            self._stats.utilization_percent,
            {"service.name": self._service_name}
        )

    def _observe_max_lag(self, options: CallbackOptions):
        """Callback for max lag gauge."""
        yield Observation(
            self._stats.max_lag_seconds,
            {"service.name": self._service_name}
        )

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

                # Sleep for the monitoring interval
                await asyncio.sleep(self._interval)

                # Measure actual elapsed time
                elapsed = loop.time() - start

                # Calculate lag (excess time beyond requested sleep)
                lag = max(0, elapsed - self._interval)

                # Update statistics
                self._stats.lag_seconds = lag
                self._stats.total_measurements += 1

                # Track maximum lag
                if lag > self._stats.max_lag_seconds:
                    self._stats.max_lag_seconds = lag

                # Count active tasks
                all_tasks = asyncio.all_tasks()
                self._stats.active_tasks = len([t for t in all_tasks if not t.done()])

                # Calculate utilization (simplified: lag/interval ratio)
                # High lag = high utilization (loop was busy)
                self._busy_time += lag
                self._total_time += self._interval
                if self._total_time > 0:
                    self._stats.utilization_percent = min(100, (self._busy_time / self._total_time) * 100)

                # Record lag in histogram for distribution analysis
                self._lag_histogram.record(
                    lag,
                    {"service.name": self._service_name}
                )

                # Detect blocking events
                if lag > self._blocking_threshold:
                    self._stats.blocking_events += 1

                    # Determine severity
                    if lag > self._critical_threshold:
                        severity = "critical"
                    else:
                        severity = "warning"

                    self._blocking_counter.add(
                        1,
                        {
                            "service.name": self._service_name,
                            "blocking.severity": severity,
                            "blocking.lag_seconds": str(round(lag, 3))
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
            "lag_seconds": round(self._stats.lag_seconds, 6),
            "lag_ms": round(self._stats.lag_seconds * 1000, 3),
            "active_tasks": self._stats.active_tasks,
            "utilization_percent": round(self._stats.utilization_percent, 2),
            "blocking_events_total": self._stats.blocking_events,
            "max_lag_seconds": round(self._stats.max_lag_seconds, 6),
            "max_lag_ms": round(self._stats.max_lag_seconds * 1000, 3),
            "total_measurements": self._stats.total_measurements,
            "monitoring_interval_ms": self._interval * 1000,
            "blocking_threshold_ms": self._blocking_threshold * 1000,
            "status": self._get_health_status()
        }

    def _get_health_status(self) -> str:
        """Determine event loop health status based on current lag."""
        lag = self._stats.lag_seconds
        if lag < 0.01:  # < 10ms
            return "healthy"
        elif lag < self._blocking_threshold:
            return "ok"
        elif lag < self._critical_threshold:
            return "degraded"
        else:
            return "critical"

    def reset_stats(self):
        """Reset statistics (useful for testing)."""
        self._stats = EventLoopStats()
        self._busy_time = 0.0
        self._total_time = 0.0
