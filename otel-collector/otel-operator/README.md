# OpenTelemetry Operator, Collector and Cluster Monitoring Setup for Kubernetes

This guide shows you how to deploy OpenTelemetry Operator, Collector, and Cluster Monitoring in a single step using our automated setup script.

## 📋 Prerequisites

Before running the script, ensure you have:

- ✅ **Kubernetes Cluster**: A running Kubernetes cluster
- ✅ **kubectl**: Configured and connected to your cluster
- ✅ **helm**: Installed (v3.9+)
- ✅ **git**: Installed
- ✅ **Last9 OTLP Endpoint and Token**: https://app.last9.io/integrations?category=all&search_term=op&integration=OpenTelemetry --> Copy the OTLP endpoint URL and the Auth header token
- ✅ **Last9 Monitoring Endpoint and username & Password**: https://app.last9.io/integrations?category=all&search_term=prome&integration=Prometheus --> Copy the remote write URL and Values of username & password

## 🎯 Conflict-Free Installation

**Zero Conflicts Guaranteed**: This setup automatically detects and resolves common OpenTelemetry installation conflicts, making it safe to install alongside existing monitoring infrastructure.

### Automatic Conflict Resolution

Our setup script includes intelligent conflict detection that:

✅ **Detects existing OpenTelemetry operators** (Dynatrace, New Relic, etc.)
✅ **Uses high ports (40000+)** to avoid port conflicts
✅ **Smart CRD strategy** (uses `--skip-crds` when existing CRDs found)
✅ **Compatible with any existing operator** installation

### High-Port Strategy

All components use conflict-free high ports instead of standard ports:

| Component | Standard Port | **Conflict-Free Port** | Purpose |
|-----------|---------------|----------------------|---------|
| **OTLP HTTP** | 4318 | **40004** | Application trace/log ingestion |
| **OTLP gRPC** | 4317 | **40005** | Application trace/log ingestion |
| **Prometheus** | 9090 | **40002** | Metrics collection |
| **Node Exporter** | 9100 | **40001** | Host metrics |
| **Kube State Metrics** | 8080 | **40003** | Kubernetes metrics |

### Why This Approach Works

- **No interference**: High ports (40000+) are rarely used by other services
- **Production proven**: Successfully eliminates conflicts in enterprise environments
- **Automatic detection**: Script detects conflicts and applies appropriate strategy
- **Backward compatible**: Existing applications work without changes

### Step 1 Quick Start - Installation Options

### Download the Setup Script

First, download the shell script from the GitHub repository:

```bash
# Download shell script directly from below link
curl -O https://raw.githubusercontent.com/last9/opentelemetry-examples/main/otel-collector/otel-operator/last9-otel-setup.sh
chmod +x last9-otel-setup.sh
```

### Installation Options

#### Option 1: Install Everything (Recommended - This will cover integration of Logs, Traces and Cluster Monitoring)
```bash
./last9-otel-setup.sh token="your-token-here" endpoint="your-endpoint-here" monitoring-endpoint="your-metrics-endpoint" username="your-username" password="your-password"
```

#### Option 2: For Traces alone --> Install OpenTelemetry Operator and collector
```bash
./last9-otel-setup.sh operator-only endpoint="your-endpoint-here" token="your-token-here" 
```

#### Option 3: For Logs use case --> Install Only Collector for Logs (No Operator)
```bash
./last9-otel-setup.sh logs-only endpoint="your-endpoint-here"  token="your-token-here" 
```

#### Option 4: Install Only Cluster Monitoring (Using Metrics)
```bash
./last9-otel-setup.sh monitoring-only monitoring-endpoint="your-metrics-endpoint" username="your-username" password="your-password"
```

---

## 🌍 Environment Configuration (Optional)

```bash
# Combined with monitoring and tolerations
./last9-otel-setup.sh \
  token="your-token" \
  endpoint="your-endpoint" \
  monitoring-endpoint="your-metrics-endpoint" \
  username="your-username" \
  password="your-password" \
  env=production
```

---

## 🎯 Advanced Configuration (Optional)

### Cluster Name Override

By default, the cluster name is auto-detected from your kubectl current context. You can override it using the `cluster=` parameter:

```bash
# Set custom cluster name
./last9-otel-setup.sh \
  token="your-token" \
  endpoint="your-endpoint" \
  cluster=prod-us-east-1

# Combined with environment
./last9-otel-setup.sh \
  token="your-token" \
  endpoint="your-endpoint" \
  env=production \
  cluster=prod-us-east-1

# Full setup with cluster name
./last9-otel-setup.sh \
  token="your-token" \
  endpoint="your-endpoint" \
  monitoring-endpoint="your-metrics-endpoint" \
  username="your-username" \
  password="your-password" \
  env=production \
  cluster=my-k8s-cluster
```

**Why override cluster name?**
- When kubectl context name doesn't match your preferred cluster identifier
- For consistent naming across multiple environments
- When auto-detection doesn't provide meaningful names

---

### Kubernetes Tolerations and NodeSelector

If your nodes **ARE tainted**, you need both tolerations and nodeSelector:

```yaml
# tolerations.yaml
tolerations:
  - key: "monitoring"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"

nodeSelector:
  monitoring: "true"

nodeExporterTolerations:
  - operator: "Exists"
```

**Components that receive tolerations and nodeSelector:**
- OpenTelemetry Operator
- OpenTelemetry Collector (DaemonSet)
- Prometheus Agent
- Kube-State-Metrics
- Prometheus Operator
- Kube-Operator

**Note:** node-exporter DaemonSet only receives `nodeExporterTolerations` (no nodeSelector) to ensure it runs on ALL nodes for complete metrics collection.

**Usage:**
```bash
# IMPORTANT: tolerations-file must be an absolute path
./last9-otel-setup.sh \
  tolerations-file=/absolute/path/to/tolerations.yaml \
  token="your-token" \
  endpoint="your-endpoint" \
  monitoring-endpoint="your-metrics-endpoint" \
  username="your-username" \
  password="your-password"

# Example with full path
./last9-otel-setup.sh \
  tolerations-file=/home/user/k8s/tolerations.yaml \
  token="your-token" ...
```

**Path Requirements:**
- ✅ Must be an absolute path (starts with `/`)
- ✅ File must exist and be readable
- ❌ Relative paths (e.g., `./tolerations.yaml`) are not supported

---

### Step 2: Verify Installation

Check that all pods are up and running:

```bash
# Check all pods in last9 namespace should be up and running
kubectl get pods -n last9
```

### Step 3: Annotate Your Application

Add this annotation to your application deployment to enable auto-instrumentation:

```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "last9/l9-instrumentation"
```

**Example deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-java-app
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-java: "last9/l9-instrumentation"  # ← Enable auto-instrumentation
    spec:
      containers:
      - name: my-app
        image: my-java-app:latest
```

### In case you want to uninstall any or all components, use the following:

```bash
./last9-otel-setup.sh uninstall-all
```

## 🔧 Troubleshooting & Conflict Resolution

### Conflict Resolution Status

The setup script automatically runs conflict resolution. You'll see output like:

```
🔧 Running conflict resolution analysis...
🎯 Starting Last9 OpenTelemetry conflict resolution...
✅ Kubernetes cluster connectivity verified
🔍 Checking for existing OpenTelemetry operator installations...
✅ No existing OpenTelemetry operator found
🔍 Determining CRD installation strategy...
📋 Strategy: Install CRDs normally (no existing CRDs found)
✅ No port conflicts detected on standard ports
✅ Conflict resolution completed successfully!

🔧 Port Configuration:
   • OTLP HTTP: 40004 (instead of 4318)
   • OTLP gRPC: 40005 (instead of 4317)
   • Prometheus: 40002 (instead of 9090)
   • Node Exporter: 40001 (instead of 9100)
   • Kube State Metrics: 40003 (instead of 8080)
```

### Common Scenarios

#### ✅ Existing Operator Found
```
⚠️  Found existing OpenTelemetry operator:
   Namespace: opentelemetry-system
   Managed by: Helm
   Version: 0.89.0
✅ Existing operator is Helm-managed - compatible with Last9 approach
🎯 Will use --skip-crds flag to avoid CRD ownership conflicts
```

#### ✅ Port Conflicts Detected
```
⚠️  Port conflict detected: 4318 is in use by existing services
🎯 Solution: Using high ports (40000+) to avoid all conflicts
```

### Manual Verification

If you want to verify the conflict-free setup:

```bash
# Check if Last9 components are using high ports
kubectl get svc -n last9 -o wide

# Verify OTLP endpoints in instrumentation
kubectl get instrumentation l9-instrumentation -o yaml | grep -A5 OTEL_EXPORTER_OTLP_ENDPOINT

# Check for existing OpenTelemetry operators
kubectl get deployments --all-namespaces -l app.kubernetes.io/name=opentelemetry-operator
```

### Disabling Conflict Resolution

If you need to disable automatic conflict resolution:

```bash
# Set environment variable to disable
CONFLICT_RESOLUTION_ENABLED=false ./last9-otel-setup.sh token="..." endpoint="..."
```

**Note**: Only disable if you're certain no conflicts exist in your environment.

## 📚 Additional Resources

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Last9 Documentation](https://docs.last9.io/)
- [Individual Functions Usage Guide](INDIVIDUAL_FUNCTIONS_USAGE.md)

