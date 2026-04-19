"""
Programmatic sample for the l9gpu Python package.

Reads per-GPU telemetry on the local host using NVML and optionally
computes per-GPU cost metrics based on the detected cloud instance type.

Run:
    pip install l9gpu
    python read_gpus.py

Requires NVIDIA driver + NVML on the host. On machines without GPUs the
script prints a note and exits cleanly.
"""

from __future__ import annotations

import sys

from l9gpu.monitoring.cost_monitor import (
    compute_cost_metrics,
    detect_instance_type,
    get_cost_per_gpu_hour,
)
from l9gpu.monitoring.device_telemetry_nvml import (
    DeviceTelemetryException,
    NVMLDeviceTelemetryClient,
)


def main() -> int:
    try:
        client = NVMLDeviceTelemetryClient()
    except DeviceTelemetryException as exc:
        print(f"NVML unavailable on this host: {exc}", file=sys.stderr)
        return 0

    instance = detect_instance_type() or "unknown"
    cost_per_gpu_hr = get_cost_per_gpu_hour(instance) or 0.0
    print(f"instance: {instance}  (cost/GPU/hr ${cost_per_gpu_hr:.2f})")
    print(
        f"{'idx':>3}  {'name':20}  {'util%':>6}  {'mem_used_mib':>12}  "
        f"{'temp_c':>6}  {'power_w':>8}  {'$/hr':>6}"
    )

    count = client.get_device_count()
    for idx in range(count):
        dev = client.get_device_by_index(idx)
        util = dev.get_utilization_rates()
        mem = dev.get_memory_info()
        power_mw = dev.get_power_usage() or 0
        power_w = power_mw / 1000.0

        cost = compute_cost_metrics(
            gpu_index=idx,
            power_draw_watts=power_w,
            gpu_util=util.gpu / 100.0,
            prompt_tokens_per_sec=None,
            generation_tokens_per_sec=None,
            cost_per_gpu_hour=cost_per_gpu_hr,
        )

        print(
            f"{idx:>3}  {dev.get_name()[:20]:20}  "
            f"{util.gpu:>6.1f}  {mem.used // (1024 * 1024):>12}  "
            f"{dev.get_temperature():>6}  {power_w:>8.1f}  "
            f"{cost.usd_per_hour:>6.2f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
