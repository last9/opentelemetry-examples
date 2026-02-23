"""
Event Loop Diagnostics for Python Asyncio Applications with OpenTelemetry
Monitors event loop health and exports metrics via OTEL
"""
import asyncio
import time
import traceback
from typing import Optional, Dict, Any
from dataclasses import dataclass

from opentelemetry import metrics
from opentelemetry.metrics import Histogram, UpDownCounter, Counter, ObservableGauge


@dataclass
class EventLoopState:
    """Current state of the event loop"""
    lag_ms: float = 0.0
    active_tasks: int = 0
    max_lag_ms: float = 0.0
    blocking_events_total: int = 0
    total_measurements: int = 0
    utilization_percent: float = 0.0


class EventLoopDiagnostics:
    """
    Event Loop Diagnostics Monitor with OpenTelemetry Integration

    Monitors event loop health and exports metrics to OTEL collectors.
    Works seamlessly with Sanic and other asyncio frameworks.
    """

    def __init__(
        self,
        meter_name: str = "sanic.event_loop",
        check_interval_ms: float = 100,
        blocking_threshold_ms: float = 50,
        enabled: bool = True,
        service_name: str = "sanic-service"
    ):
        """
        Initialize event loop diagnostics with OTEL

        Args:
            meter_name: Name of the OTEL meter
            check_interval_ms: How often to check event loop lag (default 100ms)
            blocking_threshold_ms: Threshold to consider operation as blocking (default 50ms)
            enabled: Whether monitoring is enabled
            service_name: Name of the service for metric attributes
        """
        self.check_interval_ms = check_interval_ms
        self.blocking_threshold_ms = blocking_threshold_ms
        self.enabled = enabled
        self.service_name = service_name

        # State tracking
        self._state = EventLoopState()
        self._monitor_task: Optional[asyncio.Task] = None
        self._last_check_time = time.perf_counter()
        self._busy_time = 0.0
        self._total_time = 0.0

        # Initialize OTEL Meter
        self._meter = metrics.get_meter(meter_name, "1.0.0")
        self._setup_metrics()

    def _setup_metrics(self):
        """Setup OTEL metric instruments"""

        # Histogram for event loop lag distribution
        self.lag_histogram: Histogram = self._meter.create_histogram(
            name="event_loop.lag",
            description="Event loop lag in milliseconds",
            unit="ms"
        )

        # Counter for active tasks (up/down counter)
        self.active_tasks_counter: UpDownCounter = self._meter.create_up_down_counter(
            name="event_loop.tasks.active",
            description="Number of active asyncio tasks",
            unit="{tasks}"
        )

        # Counter for blocking calls
        self.blocking_calls_counter: Counter = self._meter.create_counter(
            name="event_loop.blocking_calls",
            description="Total number of blocking operations detected",
            unit="{calls}"
        )

        # Observable Gauge for utilization (callback-based)
        self.utilization_gauge: ObservableGauge = self._meter.create_observable_gauge(
            name="event_loop.utilization",
            description="Event loop utilization percentage",
            unit="%",
            callbacks=[self._observe_utilization]
        )

        # Observable Gauge for max lag
        self.max_lag_gauge: ObservableGauge = self._meter.create_observable_gauge(
            name="event_loop.max_lag",
            description="Maximum event loop lag observed",
            unit="ms",
            callbacks=[self._observe_max_lag]
        )

        # Histogram for request wait time
        self.wait_time_histogram: Histogram = self._meter.create_histogram(
            name="event_loop.wait_time",
            description="Time spent waiting to acquire event loop per request",
            unit="ms"
        )

        # Histogram for request execution time
        self.execution_time_histogram: Histogram = self._meter.create_histogram(
            name="event_loop.execution_time",
            description="Time spent executing on event loop per request",
            unit="ms"
        )

    def _observe_utilization(self, options):
        """Callback for utilization gauge"""
        yield metrics.Observation(
            self._state.utilization_percent,
            {"service.name": self.service_name}
        )

    def _observe_max_lag(self, options):
        """Callback for max lag gauge"""
        yield metrics.Observation(
            self._state.max_lag_ms,
            {"service.name": self.service_name}
        )

    async def start(self):
        """Start the event loop monitoring background task"""
        if not self.enabled or self._monitor_task is not None:
            return

        print(f"[EventLoopDiagnostics] Starting monitor for {self.service_name}")
        self._monitor_task = asyncio.create_task(self._monitor_loop())

    async def stop(self):
        """Stop the event loop monitoring"""
        if self._monitor_task:
            print(f"[EventLoopDiagnostics] Stopping monitor for {self.service_name}")
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass
            self._monitor_task = None

    async def _monitor_loop(self):
        """Background task that continuously monitors event loop health"""
        loop = asyncio.get_event_loop()

        while True:
            try:
                await asyncio.sleep(self.check_interval_ms / 1000)
                await self._check_lag(loop)
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"[EventLoopDiagnostics] Error in monitor: {e}")
                traceback.print_exc()

    async def _check_lag(self, loop):
        """Measure current event loop lag"""
        scheduled_time = time.perf_counter()

        # Schedule a callback to measure lag
        future = asyncio.Future()

        def callback():
            actual_time = time.perf_counter()
            lag = (actual_time - scheduled_time) * 1000  # Convert to ms
            future.set_result(lag)

        loop.call_soon(callback)
        lag_ms = await future

        # Update state
        self._state.lag_ms = lag_ms
        self._state.total_measurements += 1

        # Track max lag
        if lag_ms > self._state.max_lag_ms:
            self._state.max_lag_ms = lag_ms

        # Count blocking events
        if lag_ms > self.blocking_threshold_ms:
            self._state.blocking_events_total += 1
            self.blocking_calls_counter.add(
                1,
                {"service.name": self.service_name, "operation": "event_loop_check"}
            )

        # Count active tasks
        all_tasks = asyncio.all_tasks(loop)
        self._state.active_tasks = len(all_tasks)

        # Calculate utilization
        current_time = time.perf_counter()
        elapsed = current_time - self._last_check_time
        self._total_time += elapsed

        if lag_ms > self.check_interval_ms:
            self._busy_time += elapsed

        if self._total_time > 0:
            self._state.utilization_percent = (self._busy_time / self._total_time) * 100

        self._last_check_time = current_time

        # Record lag to histogram
        self.lag_histogram.record(
            lag_ms,
            {"service.name": self.service_name}
        )

    def get_current_state(self) -> EventLoopState:
        """Get current event loop state snapshot"""
        return EventLoopState(
            lag_ms=self._state.lag_ms,
            active_tasks=self._state.active_tasks,
            max_lag_ms=self._state.max_lag_ms,
            blocking_events_total=self._state.blocking_events_total,
            total_measurements=self._state.total_measurements,
            utilization_percent=self._state.utilization_percent
        )

    def record_request_metrics(
        self,
        wait_time_ms: float,
        execution_time_ms: float,
        endpoint: str,
        attributes: Optional[Dict[str, Any]] = None
    ):
        """
        Record per-request event loop metrics (similar to New Relic's approach)

        Args:
            wait_time_ms: Time spent waiting to acquire the event loop
            execution_time_ms: Time spent executing on the event loop
            endpoint: HTTP endpoint path
            attributes: Additional custom attributes
        """
        base_attributes = {
            "service.name": self.service_name,
            "endpoint": endpoint
        }

        if attributes:
            base_attributes.update(attributes)

        self.wait_time_histogram.record(wait_time_ms, base_attributes)
        self.execution_time_histogram.record(execution_time_ms, base_attributes)
