# Event Loop Monitoring - Frequently Asked Questions

This document answers common questions about Python asyncio event loop monitoring using OpenTelemetry.

## Table of Contents

1. [Understanding Event Loop Metrics](#understanding-event-loop-metrics)
2. [Common Questions](#common-questions)
3. [Using Operation Labels](#using-operation-labels)
4. [Grafana Queries](#grafana-queries)
5. [Production Best Practices](#production-best-practices)

---

## Understanding Event Loop Metrics

### Key Metrics Explained

| Metric | Unit | What It Measures | Update Frequency |
|--------|------|-----------------|------------------|
| **Event Loop Lag** | milliseconds | Delay between task scheduling and execution (instantaneous) | Every 100ms |
| **Event Loop Utilization** | percentage (0-100%) | Average time the loop was busy over a time window | Cumulative |
| **Max Lag** | milliseconds | Worst-case blocking event since startup (high water mark) | Never decreases |
| **Active Tasks** | count | Number of currently running async tasks | Every 100ms |
| **Blocking Events** | count | Number of times lag exceeded threshold (50ms default) | On each occurrence |

---

## Common Questions

### Q1: Event loop lag shows 300ms but utilization is only 9% - how is this possible?

**Answer:** This is normal and expected behavior. The two metrics measure different aspects:

- **Lag (300ms)** = Instantaneous delay at a specific moment (spiky)
- **Utilization (9%)** = Average busy time over a longer window (smoothed)

**Example:**
```
Timeline over 3 seconds:
[----300ms block----][2700ms healthy async work]

Lag:         300ms (at that moment)
Utilization: 300ms / 3000ms = 10% (averaged over 3s)
```

**Why this matters:**
- **Low utilization + high lag spikes** = Occasional blocking (good - you can fix specific operations)
- **High utilization + high lag** = Constant blocking (bad - systemic performance issue)

**What to do:**
- Use the `operation` label to identify which endpoints cause lag spikes
- Fix those specific blocking operations
- Don't worry if utilization stays low - that means most of your code is non-blocking!

---

### Q2: How do I identify which operation is blocking the event loop?

**Answer:** The `asyncio.eventloop.blocking_events` metric now includes an **`operation` label** that shows the HTTP endpoint causing the block.

**Example metric:**
```
asyncio_eventloop_blocking_events_total{
  service_name="my-service",
  operation="GET /api/users",
  blocking_severity="warning",
  blocking_lag_ms="245.5"
} 3
```

This tells you:
- Endpoint: `GET /api/users`
- Severity: `warning` (50-500ms) or `critical` (>500ms)
- Lag: 245.5ms
- Count: 3 blocking events

**How it works:**
1. Background monitor detects event loop lag > 50ms
2. Request middleware checks if blocking occurred during a specific HTTP request
3. If yes, records the operation name (HTTP method + path)
4. Metric exported with `operation` label

---

### Q3: Max lag is showing seconds (e.g., 1.25s) - what does this mean?

**Answer:** **Max lag = 1.25 seconds** means the worst blocking event since application startup lasted 1.25 full seconds.

**What happens during 1.25s of blocking:**
- ❌ No new HTTP requests can be processed
- ❌ No async tasks can run (websockets freeze, background jobs pause)
- ❌ The entire application appears "hung"
- ❌ User-facing timeout errors (if response time SLA < 1.25s)

**Why this happens:**

1. **Multiple blocking operations overlapping:**
   ```python
   # Three blocking operations running simultaneously
   Request 1: /cpu-bound (500ms)
   Request 2: /blocking-io (300ms)  } All blocking the
   Request 3: /blocking-hash (450ms)} same event loop

   Total blocking: ~1250ms
   ```

2. **Heavy synchronous CPU work:**
   ```python
   # BAD - blocks event loop
   def compute():
       result = 0
       for i in range(100_000_000):  # Takes 1+ seconds
           result += i
       return result

   # GOOD - offloads to thread pool
   loop = asyncio.get_running_loop()
   result = await loop.run_in_executor(thread_pool, compute)
   ```

3. **Synchronous I/O operations:**
   ```python
   # BAD - blocks event loop
   time.sleep(1)  # Freezes everything

   # GOOD - non-blocking
   await asyncio.sleep(1)  # Allows other tasks to run
   ```

**How to find the culprit:**

Use Grafana query to see which operation caused the worst blocking:
```promql
asyncio_eventloop_blocking_events_total{
  blocking_severity="critical"
}
```

Group by `operation` to see breakdown:
```promql
sum by (operation) (
  increase(asyncio_eventloop_blocking_events_total{
    blocking_severity="critical"
  }[5m])
)
```

**What to do in production:**
1. Set alert: `max_lag_ms > 500` (critical threshold)
2. Identify blocking operation using `operation` label
3. Fix the code:
   - Offload CPU work to thread pool
   - Replace `time.sleep()` with `asyncio.sleep()`
   - Use async database drivers (asyncpg, motor, etc.)
   - Use async HTTP clients (aiohttp, httpx)

---

## Using Operation Labels

### Available Labels

The `asyncio.eventloop.blocking_events` metric includes these labels:

| Label | Example Value | Description |
|-------|---------------|-------------|
| `service.name` | `"my-api"` | Service name from OpenTelemetry resource |
| `operation` | `"GET /api/users"` | HTTP method + path of blocking endpoint |
| `blocking.severity` | `"warning"` or `"critical"` | Severity based on lag threshold |
| `blocking.lag_ms` | `"245.5"` | Actual lag measurement in milliseconds |

### Severity Levels

| Severity | Threshold | Meaning |
|----------|-----------|---------|
| `warning` | 50ms - 500ms | Noticeable delay, should be investigated |
| `critical` | > 500ms | Severe blocking, immediate action needed |

---

## Grafana Queries

### Basic Queries

**Total blocking events over time:**
```promql
increase(asyncio_eventloop_blocking_events_total[5m])
```

**Blocking events grouped by operation:**
```promql
sum by (operation) (
  increase(asyncio_eventloop_blocking_events_total[5m])
)
```

**Only critical blocking events:**
```promql
increase(asyncio_eventloop_blocking_events_total{
  blocking_severity="critical"
}[5m])
```

### Advanced Queries

**Top 5 most problematic endpoints:**
```promql
topk(5,
  sum by (operation) (
    increase(asyncio_eventloop_blocking_events_total[1h])
  )
)
```

**Blocking rate per minute:**
```promql
rate(asyncio_eventloop_blocking_events_total[1m]) * 60
```

**Find operations with lag > 1 second:**
```promql
asyncio_eventloop_blocking_events_total{
  blocking_lag_ms=~"[1-9][0-9][0-9][0-9].*"
}
```

**Correlation: Lag vs Active Tasks:**
```promql
# Show both on same graph
asyncio_eventloop_lag (metric 1)
asyncio_eventloop_active_tasks (metric 2)
```

### Dashboard Panels

**Event Loop Health Status:**
```promql
# Returns 1 for healthy, 0 for degraded
(asyncio_eventloop_lag < 10)
or
(asyncio_eventloop_lag >= 10 and asyncio_eventloop_lag < 50)
or
(asyncio_eventloop_lag >= 50)
```

Use value mappings:
- `< 10ms` → Healthy (green)
- `10-50ms` → OK (yellow)
- `> 50ms` → Degraded (red)

---

## Production Best Practices

### 1. Set Alerts

**Critical Blocking Alert:**
```promql
max_over_time(asyncio_eventloop_lag[5m]) > 500
```

**Frequent Blocking Alert:**
```promql
increase(asyncio_eventloop_blocking_events_total[5m]) > 10
```

**High Utilization Alert:**
```promql
asyncio_eventloop_utilization > 80
```

### 2. Monitoring Strategy

**For each service:**
- ✅ Track P95 and P99 lag (not just average)
- ✅ Monitor blocking events per endpoint
- ✅ Correlate lag spikes with deployment events
- ✅ Set SLOs based on user-facing latency requirements

**Example SLO:**
- P95 lag < 50ms (warning threshold)
- P99 lag < 200ms (acceptable)
- Max lag < 500ms (critical - requires immediate fix)

### 3. Debugging Blocking Operations

When you see a blocking event:

1. **Identify the operation:**
   ```promql
   asyncio_eventloop_blocking_events_total{operation="GET /slow-endpoint"}
   ```

2. **Check the code for common issues:**
   - ❌ `time.sleep()` → ✅ `await asyncio.sleep()`
   - ❌ `requests.get()` → ✅ `await httpx.get()`
   - ❌ Heavy CPU loop → ✅ `await loop.run_in_executor()`
   - ❌ Sync DB query → ✅ Async driver (asyncpg, motor)

3. **Verify the fix:**
   - Monitor lag for that operation
   - Ensure blocking events decrease
   - Check P95/P99 latency improvements

### 4. Optimization Patterns

**Pattern 1: Offload CPU work**
```python
# Before (blocks event loop)
def heavy_computation(data):
    return sum(i ** 2 for i in data)

result = heavy_computation(large_dataset)

# After (non-blocking)
loop = asyncio.get_running_loop()
result = await loop.run_in_executor(
    thread_pool,
    heavy_computation,
    large_dataset
)
```

**Pattern 2: Batch processing**
```python
# Before (blocks event loop for entire batch)
for item in large_batch:
    process_item(item)

# After (allows other tasks to run between items)
for item in large_batch:
    await process_item_async(item)
    await asyncio.sleep(0)  # Yield to event loop
```

**Pattern 3: Async context managers**
```python
# Before (synchronous I/O)
with open('file.txt') as f:
    data = f.read()

# After (non-blocking I/O)
async with aiofiles.open('file.txt') as f:
    data = await f.read()
```

---

## Metric Reference

### OpenTelemetry Metrics Exported

| Metric Name | Type | Unit | Labels | Description |
|-------------|------|------|--------|-------------|
| `asyncio.eventloop.lag` | Gauge | ms | `service.name` | Current event loop lag |
| `asyncio.eventloop.max_lag` | Gauge | ms | `service.name` | Maximum lag since startup |
| `asyncio.eventloop.active_tasks` | Gauge | tasks | `service.name` | Number of active asyncio tasks |
| `asyncio.eventloop.utilization` | Gauge | % | `service.name` | Event loop busy percentage |
| `asyncio.eventloop.blocking_events` | Counter | events | `service.name`, `operation`, `blocking.severity`, `blocking.lag_ms` | Count of blocking events with operation labels |
| `asyncio.eventloop.lag_distribution` | Histogram | ms | `service.name` | Distribution of lag measurements for percentile analysis |
| `asyncio.eventloop.task.active_count` | Gauge | tasks | `service.name`, `task.coroutine` | Active tasks by coroutine name |
| `asyncio.eventloop.task.lag_contribution` | Histogram | ms | `service.name`, `task.coroutine`, `blocking.severity` | Lag attributed to specific coroutine types |

---

## Troubleshooting

### Issue: No operation labels appearing

**Possible causes:**
1. Middleware not registered correctly
2. Requests completing before blocking detection
3. Blocking happening outside HTTP request context

**Solution:**
Check middleware registration and ensure requests last long enough for blocking detection.

### Issue: False positives (non-blocking operations labeled as blocking)

**Possible causes:**
1. Overlapping requests during blocking window
2. Timing race conditions

**Solution:**
This should be fixed in the latest version. The middleware now uses both "stamped block" and "in-flight block" detection to accurately attribute blocking.

### Issue: Max lag keeps increasing

**Possible causes:**
1. Actual blocking operations in production
2. Resource exhaustion (CPU, memory)
3. External dependency slowdowns

**Solution:**
1. Identify operation using `operation` label
2. Profile the blocking code
3. Implement async patterns or offload to thread pool

---

## Additional Resources

- [Python asyncio documentation](https://docs.python.org/3/library/asyncio.html)
- [OpenTelemetry Python SDK](https://opentelemetry.io/docs/languages/python/)
- [Event Loop Best Practices](https://docs.python.org/3/library/asyncio-dev.html)
- [Last9 Observability Guide](https://docs.last9.io/)

---

## Support

For questions or issues:
1. Check the [README.md](./README.md) for setup instructions
2. Review this FAQ for common questions
3. Examine the code in `event_loop_monitor.py` for implementation details
4. Check Grafana dashboards for metric visualization examples
