# GPU Telemetry with l9gpu

Vendor-agnostic GPU observability for Kubernetes and Slurm clusters, exporting OTLP to Last9.

`l9gpu` normalizes NVIDIA (NVML/DCGM), AMD (amdsmi), and Intel Gaudi (hl-smi) into the
OpenTelemetry `gpu.*` namespace and attaches workload attribution — so every GPU metric
carries the pod, namespace, job, and user that owns the load.

## What you get

- Per-GPU utilization, memory, temperature, power (all three vendors)
- Workload attribution: `k8s.pod.name`, `k8s.namespace.name`, `k8s.deployment.name`,
  `slurm.job.id`, `slurm.user`, `slurm.partition`
- Fleet health: XID errors, ECC trends, NCCL errors, thermal throttling
- Cost attribution: `$/token`, `tokens/watt`, idle-GPU cost

## Install (Helm, Kubernetes)

```bash
# Add the repo
helm repo add l9gpu https://last9.github.io/gpu-telemetry
helm repo update

# Install with your Last9 OTLP credentials
helm install l9gpu l9gpu/l9gpu \
  --namespace l9gpu --create-namespace \
  --set otlp.endpoint=otlp.last9.io:443 \
  --set otlp.headers.authorization="Basic $LAST9_AUTH_HEADER"
```

See [`values.yaml`](./values.yaml) for a production-grade example with RBAC,
resource limits, node selectors for GPU nodes, and alerting enabled.

## Install (Slurm, bare-metal)

```bash
# Install the Python agent on every GPU node
pip install l9gpu

# Run the collector with the provided systemd units
sudo cp systemd/*.service /etc/systemd/system/
sudo systemctl enable --now l9gpu_nvml_monitor slurm_monitor
```

## Verify data in Last9

After ~1 minute, check [app.last9.io/metrics](https://app.last9.io/metrics):

```promql
# Per-pod GPU utilization
avg by (k8s.pod.name, gpu.uuid) (gpu_utilization)

# Cluster-wide idle GPUs (utilization < 5% for 15m)
count(avg_over_time(gpu_utilization[15m]) < 5)

# Power draw per namespace
sum by (k8s.namespace.name) (gpu_power_watts)
```

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](./values.yaml) | Production Helm values (RBAC, limits, GPU node selector) |
| [`collector-config.yaml`](./collector-config.yaml) | Standalone OTel Collector config (no Helm) |
| [`deploy.sh`](./deploy.sh) | One-shot deploy script |

## Why l9gpu over alternatives

| Capability | `l9gpu` | DCGM Exporter | NVIDIA GPU Operator | Datadog GPU |
|------------|---------|---------------|---------------------|-------------|
| NVIDIA support | ✅ | ✅ | ✅ | ✅ |
| AMD support | ✅ | ❌ | ❌ | ❌ |
| Intel Gaudi support | ✅ | ❌ | ❌ | ❌ |
| Workload attribution (pod/job) | ✅ built-in | ❌ (DIY) | ❌ (DIY) | ✅ |
| Slurm HPC attribution | ✅ | ❌ | ❌ | ❌ |
| OTLP-native | ✅ | ❌ (Prometheus only) | ❌ | ❌ (proprietary agent) |
| Vendor-neutral backend | ✅ (any OTLP) | ✅ (Prometheus) | ✅ (Prometheus) | ❌ (Datadog only) |
| Open source | ✅ MIT | ✅ | ✅ | ❌ |
| Cost / fleet efficiency metrics | ✅ | ❌ | ❌ | ✅ |

Source: [github.com/last9/gpu-telemetry](https://github.com/last9/gpu-telemetry)
