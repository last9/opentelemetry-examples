# Go eBPF Auto-Instrumentation Demo

This example demonstrates **zero-code** OpenTelemetry instrumentation for Go using eBPF. Unlike SDK-based instrumentation, this approach requires no code changes to your application.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Pod                          │
│                                                             │
│  ┌─────────────────────┐     ┌─────────────────────────┐   │
│  │   Your Go App       │     │  eBPF Instrumentation   │   │
│  │   (no SDK needed)   │◄────│  Sidecar (injected)     │   │
│  │                     │     │                         │   │
│  │  - net/http         │     │  Hooks into kernel to   │   │
│  │  - database/sql     │     │  trace function calls   │   │
│  │  - gRPC             │     │                         │   │
│  └─────────────────────┘     └─────────────────────────┘   │
│                                        │                    │
│                                        ▼                    │
│                              OTel Collector → Last9         │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Last9 OpenTelemetry Operator** installed in your cluster
2. **Linux kernel 4.4+** (5.x recommended) on cluster nodes
3. **Go 1.17+** used to compile the application

## Quick Start

### 1. Build the Docker Image

```bash
# Build locally
docker build -t go-ebpf-demo:latest .

# Or for a registry
docker build -t your-registry/go-ebpf-demo:latest .
docker push your-registry/go-ebpf-demo:latest
```

### 2. Update Image Reference (if using registry)

```bash
# Edit k8s/deployment.yaml and update the image
sed -i 's|go-ebpf-demo:latest|your-registry/go-ebpf-demo:latest|g' k8s/deployment.yaml
```

### 3. Deploy to Kubernetes

```bash
kubectl apply -f k8s/deployment.yaml
```

### 4. Verify Instrumentation

```bash
# Check pod has 2 containers (app + eBPF sidecar)
kubectl get pods -l app=go-ebpf-demo
# Expected: go-ebpf-demo-xxx   2/2   Running

# Check sidecar was injected
kubectl describe pod -l app=go-ebpf-demo | grep -A5 "Containers:"
```

### 5. Generate Traffic

```bash
# Port forward
kubectl port-forward svc/go-ebpf-demo 8080:80 &

# Generate some requests
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/api/users
curl http://localhost:8080/api/users/1
curl http://localhost:8080/api/slow
```

### 6. View Traces in Last9

Open your Last9 dashboard to see traces automatically captured from:
- HTTP requests (method, path, status code, latency)
- Database queries (if DATABASE_URL is configured)

## Key Configuration

### Required Annotation

```yaml
annotations:
  instrumentation.opentelemetry.io/inject-go: "true"
```

### Required Pod Spec

```yaml
spec:
  shareProcessNamespace: true  # Allows sidecar to access Go process
```

### Required Environment Variable

```yaml
env:
- name: OTEL_GO_AUTO_TARGET_EXE
  value: "/app/server"  # Path to your Go binary
```

## What Gets Traced Automatically

| Library | What's Captured |
|---------|-----------------|
| `net/http` | Incoming requests, method, path, status, latency |
| `database/sql` | Query execution time, operation type |
| `google.golang.org/grpc` | RPC calls, method, status |
| `github.com/gin-gonic/gin` | Route patterns, handlers |
| `github.com/gorilla/mux` | Route patterns |

## Comparison: eBPF vs SDK

| Aspect | eBPF (This Example) | SDK |
|--------|---------------------|-----|
| Code changes | None | Import + init |
| Custom spans | Not supported | Fully supported |
| Environment | Kubernetes only | Anywhere |
| Setup complexity | Low (just annotations) | Medium (code changes) |

## Troubleshooting

### Pod Shows 1/1 Instead of 2/2

The eBPF sidecar wasn't injected. Check:

```bash
# Verify operator is running
kubectl get pods -n last9 | grep operator

# Check instrumentation resource exists
kubectl get instrumentation -n last9

# Verify annotation is on pod spec (not deployment metadata)
kubectl get deployment go-ebpf-demo -o yaml | grep -A3 "annotations:"
```

### No Traces Appearing

```bash
# Check sidecar logs
kubectl logs -l app=go-ebpf-demo -c opentelemetry-auto-instrumentation-go

# Verify binary path is correct
kubectl exec -l app=go-ebpf-demo -c app -- ls -la /app/server

# Check OTEL_GO_AUTO_TARGET_EXE matches
kubectl exec -l app=go-ebpf-demo -c app -- printenv | grep OTEL
```

### Permission Errors

Ensure `shareProcessNamespace: true` is set in the pod spec.

## Files

```
ebpf/
├── main.go              # Simple HTTP server (no OTel SDK)
├── go.mod               # Go module definition
├── Dockerfile           # Multi-stage build
├── k8s/
│   └── deployment.yaml  # Kubernetes deployment with eBPF annotations
└── README.md            # This file
```

## Learn More

- [Last9 Go eBPF Documentation](https://last9.io/docs/integrations/languages/go/)
- [OpenTelemetry Go Auto-Instrumentation](https://opentelemetry.io/docs/zero-code/go/)
- [eBPF Introduction](https://ebpf.io/what-is-ebpf/)
