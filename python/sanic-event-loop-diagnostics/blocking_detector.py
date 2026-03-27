"""
Blocking Call Detector — Identifies WHICH request and WHAT operation blocked the event loop.

The sleep-based monitor (event_loop_monitor.py) answers: "Is the event loop healthy?"
This module answers: "WHO blocked it and WHAT did they call?"

## Why the middleware timestamp approach fails

The middleware checks if a request's [start, end] window overlaps with a detected
lag interval. Under concurrency, N requests overlap the same lag → N false positives.
The fundamental problem: the monitor wakes up AFTER the block, so it's doing forensics.

## How this module works

1. sys.addaudithook() fires AT THE MOMENT of a blocking call (time.sleep, socket.connect,
   builtins.open, subprocess.Popen, etc.) — not after.
2. At that moment, asyncio.current_task() identifies the exact task (coroutine).
3. We record: task name, blocking call type, caller file:line, and wall-clock timestamp.
4. The response middleware queries this record to get precise attribution.

This is the same approach used by:
- aiocop (https://github.com/Feverup/aiocop) — ~13us overhead per audited event
- Python's own asyncio debug mode (but we emit OTel metrics, not just logs)

## Production safety

- sys.audit hooks are C-level callbacks — very low overhead
- We only inspect events matching our filter set (not ALL audit events)
- Stack capture is optional and limited to top N frames
- Thread-safe via asyncio's single-threaded execution model
"""

import asyncio
import sys
import time
import traceback
from dataclasses import dataclass, field
from typing import Optional, Dict, List, Any, Tuple
from collections import deque
from opentelemetry.metrics import Meter


# Audit events that indicate blocking I/O when called from async context.
# These are Python sys.audit event names — NOT function calls.
# See: https://docs.python.org/3/library/audit_events.html
BLOCKING_AUDIT_EVENTS = frozenset({
    "time.sleep",
    "socket.connect",
    "socket.getaddrinfo",
    "builtins.open",
    "subprocess.Popen",
})


@dataclass
class BlockingEvent:
    """A single detected blocking call."""
    timestamp: float           # time.monotonic() when detected
    task_name: str             # asyncio task / coroutine name
    audit_event: str           # e.g., "time.sleep", "socket.connect"
    caller: str                # file:line of the caller
    stack_snippet: str         # Top N frames for debugging


@dataclass
class TaskBlockingRecord:
    """Accumulated blocking info for a specific asyncio task (request)."""
    task_name: str
    events: List[BlockingEvent] = field(default_factory=list)
    total_blocking_calls: int = 0
    first_block_time: float = 0.0
    last_block_time: float = 0.0


class BlockingDetector:
    """
    Detects blocking calls in async context using sys.audit hooks.

    Usage:
        detector = BlockingDetector(meter=meter)
        detector.install()  # Call once at startup

        # In response middleware:
        task = asyncio.current_task()
        record = detector.get_task_record(task)
        if record and record.total_blocking_calls > 0:
            span.set_attribute("blocking.calls", record.total_blocking_calls)
            span.set_attribute("blocking.operations",
                ", ".join(e.audit_event for e in record.events))
            span.set_attribute("blocking.callers",
                ", ".join(e.caller for e in record.events))

        detector.clear_task(task)  # Clean up after response
    """

    def __init__(
        self,
        meter: Optional[Meter] = None,
        stack_depth: int = 5,
        base_attributes: Optional[Dict[str, str]] = None,
    ):
        self._meter = meter
        self._stack_depth = stack_depth
        self._base_attributes = base_attributes or {}
        self._installed = False
        self._task_records: Dict[int, TaskBlockingRecord] = {}
        self._recent_events: deque = deque(maxlen=100)

        if meter:
            self._blocking_call_counter = meter.create_counter(
                name="asyncio.blocking.calls_detected",
                description="Blocking calls detected in async context via sys.audit hooks",
                unit="{calls}"
            )

    def install(self) -> None:
        """Install the sys.audit hook. Call once at application startup.

        IMPORTANT: sys.addaudithook cannot be removed once installed.
        The hook is extremely lightweight — it returns immediately for
        events not in our watched set (~0 overhead for unmatched events).
        """
        if self._installed:
            return
        sys.addaudithook(self._audit_hook)
        self._installed = True

    def _audit_hook(self, event: str, args: Tuple) -> None:
        """sys.audit callback — fires for every audited event in the process."""
        if event not in BLOCKING_AUDIT_EVENTS:
            return

        # Are we inside an async event loop?
        try:
            asyncio.get_running_loop()
        except RuntimeError:
            return  # Not in async context — blocking call is expected here

        task = asyncio.current_task()
        if task is None:
            return  # No current task (callback, not coroutine)

        task_id = id(task)
        coro = task.get_coro()
        coro_name = (
            getattr(coro, "__qualname__", None)
            or getattr(coro, "__name__", None)
            or task.get_name()
        )

        # Capture caller location
        caller = "unknown"
        stack_snippet = ""
        if self._stack_depth > 0:
            frames = traceback.extract_stack(limit=self._stack_depth + 4)
            user_frames = [
                f for f in frames
                if "blocking_detector.py" not in f.filename
                and "/asyncio/" not in f.filename
            ]
            if user_frames:
                top = user_frames[-1]
                caller = f"{top.filename}:{top.lineno}"
                stack_snippet = "\n".join(
                    f"  {f.filename}:{f.lineno} in {f.name}"
                    for f in user_frames[-self._stack_depth:]
                )

        now = time.monotonic()
        blocking_event = BlockingEvent(
            timestamp=now,
            task_name=coro_name,
            audit_event=event,
            caller=caller,
            stack_snippet=stack_snippet,
        )

        # Record per-task
        if task_id not in self._task_records:
            self._task_records[task_id] = TaskBlockingRecord(
                task_name=coro_name,
                first_block_time=now,
            )

        record = self._task_records[task_id]
        record.events.append(blocking_event)
        record.total_blocking_calls += 1
        record.last_block_time = now

        self._recent_events.append(blocking_event)

        # Emit metric with precise attribution
        if self._meter and hasattr(self, "_blocking_call_counter"):
            self._blocking_call_counter.add(
                1,
                {
                    **self._base_attributes,
                    "blocking.event": event,
                    "blocking.task": coro_name,
                    "blocking.caller": caller,
                }
            )

    def get_task_record(
        self, task: Optional[asyncio.Task] = None
    ) -> Optional[TaskBlockingRecord]:
        """Get the blocking record for a task. Zero false positives — only the
        task that actually called a blocking function will have a record."""
        if task is None:
            task = asyncio.current_task()
        if task is None:
            return None
        return self._task_records.get(id(task))

    def clear_task(self, task: Optional[asyncio.Task] = None) -> None:
        """Clean up after a task completes. Call in response middleware."""
        if task is None:
            task = asyncio.current_task()
        if task is None:
            return
        self._task_records.pop(id(task), None)

    def get_recent_events(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Recent blocking events for a diagnostic endpoint."""
        events = list(self._recent_events)[-limit:]
        return [
            {
                "task": e.task_name,
                "event": e.audit_event,
                "caller": e.caller,
                "stack": e.stack_snippet,
            }
            for e in events
        ]
