# l9gpu Python API — sample

Programmatic GPU telemetry using the [`l9gpu`](https://pypi.org/project/l9gpu/)
Python package. Read NVML counters, compute cost, publish to Last9 via OTLP —
without running the full DaemonSet.

## What this shows

- `NVMLDeviceTelemetryClient` — iterate GPUs, read utilization, memory, temp, power
- `compute_cost_metrics` — derive `$/hr`, `$/GPU/hr`, idle cost, `$/token` from GPU counters
- `detect_instance_type` + `get_cost_per_gpu_hour` — auto-detect cloud instance pricing (AWS only for now)

## Run

```bash
pip install l9gpu
python read_gpus.py
```

Example output on an `p4d.24xlarge` (A100 × 8) instance:

```
instance: p4d.24xlarge  (cost/GPU/hr $4.10)
idx  name                   util%  mem_used_mib  temp_c  power_w   $/hr
  0  NVIDIA A100-SXM4-40GB    82.0         18340      67    310.2    4.10
  1  NVIDIA A100-SXM4-40GB    79.5         18112      65    298.7    4.10
  ...
```

On machines without NVIDIA GPUs (e.g. CI runners, Apple Silicon) the script
prints `NVML unavailable` and exits 0 — safe to run in tests.

## Beyond this sample

The full agent ships OTLP to Last9 out of the box. Prefer the
[CLI / systemd / Helm deploy](../README.md) for production — this sample
is for library-level integration (custom exporters, one-off scripts,
embedding in existing Python services).
