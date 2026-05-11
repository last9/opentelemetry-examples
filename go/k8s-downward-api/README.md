# Go + Kubernetes Downward API → OTel Resource Attributes

Minimal `net/http` Go service demonstrating how to enrich OpenTelemetry
traces with [Kubernetes resource semantic conventions](https://opentelemetry.io/docs/specs/semconv/resource/k8s/)
using the Kubernetes Downward API. No Go-specific k8s detector module required.

## How It Works

1. Kubernetes Downward API exposes pod metadata (name, UID, namespace, node, IP, labels)
   as environment variables inside the container.
2. A single `OTEL_RESOURCE_ATTRIBUTES` env var composes those values into OTel's
   resource attribute format: `k8s.pod.name=$(K8S_POD_NAME),...`
3. The Go OTel SDK reads `OTEL_RESOURCE_ATTRIBUTES` automatically through
   `resource.Default()` (which calls `resource.WithFromEnv()` internally) and
   attaches them to every span.

## Attributes Emitted

| Attribute | Source |
|---|---|
| `k8s.cluster.name` | hardcoded |
| `k8s.namespace.name` | `metadata.namespace` |
| `k8s.node.name` | `spec.nodeName` |
| `k8s.pod.name` | `metadata.name` |
| `k8s.pod.uid` | `metadata.uid` |
| `k8s.pod.ip` | `status.podIP` |
| `k8s.container.name` | hardcoded |
| `k8s.deployment.name` | label `app.kubernetes.io/name` |
| `host.ip` | `status.hostIP` |
| `service.version` | label `app.kubernetes.io/version` |
| `service.namespace` | `metadata.namespace` |
| `service.instance.id` | composed |

Downward API cannot provide `k8s.deployment.name`, `k8s.cluster.name`,
`k8s.replicaset.name` directly. Workarounds:

- `k8s.deployment.name` → inject pod label `app.kubernetes.io/name`
- `k8s.cluster.name` → hardcode per environment
- For higher fidelity (replicaset, owner refs) use the Collector
  [`k8sattributes`](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/k8sattributesprocessor)
  processor — enriches server-side, requires RBAC.

## Why This Pattern

When traces carry `k8s.pod.name` as a resource attribute, Last9's
**Discover → Services → Infrastructure Metrics** panel auto-loads the
Kubernetes pod dashboard (CPU/memory/restarts/throttling per pod from
cAdvisor + kube-state-metrics). Without `k8s.pod.name`, the panel falls
back to host-based dashboards which expect `system_*` and `jvm_*` metrics.

## Prerequisites

- Docker
- [kind](https://kind.sigs.k8s.io/) — `brew install kind`
- kubectl

## Run

```bash
./setup.sh
```

Port-forward and test:

```bash
kubectl -n demo port-forward svc/go-k8s-demo 8080:8080 &
curl localhost:8080/hello
```

Watch collector spans:

```bash
kubectl -n demo logs -l app=otel-collector -f
```

Look for `Resource attributes:` block containing `k8s.pod.name`,
`k8s.namespace.name`, etc.

## Cleanup

```bash
kind delete cluster --name kind-local
```

## Send to Last9

Edit `k8s/deployment.yaml` env:

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: https://otlp.last9.io
- name: OTEL_EXPORTER_OTLP_HEADERS
  value: "Authorization=Basic <your-token>"
```

Or point the local collector at Last9 in `k8s/collector.yaml`.

## See Also

- Ruby equivalent: [`ruby/k8s-downward-api`](../../ruby/k8s-downward-api)
- [Last9 Kubernetes Operator](https://last9.io/docs/integrations/containers-and-k8s/kubernetes-operator)
  — simpler path: deploys a collector with `k8sattributes` processor
  pre-configured, no per-Deployment env block needed.
