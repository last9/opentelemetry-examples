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

## 📚 Additional Resources

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Last9 Documentation](https://docs.last9.io/)
- [Individual Functions Usage Guide](INDIVIDUAL_FUNCTIONS_USAGE.md)

