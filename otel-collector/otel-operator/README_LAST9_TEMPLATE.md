# OpenTelemetry Operator, Collector and Cluster Monitoring Setup for Kubernetes

This guide shows you how to deploy OpenTelemetry Operator, Collector, and Cluster Monitoring in a single step using our automated setup script.

## 📋 Prerequisites

Before running the script, ensure you have:

- ✅ **Kubernetes Cluster**: A running Kubernetes cluster
- ✅ **kubectl**: Configured and connected to your cluster
- ✅ **helm**: Installed (v3.9+)
- ✅ **git**: Installed


### Step 1 Quick Start - Installation Options

### Download the Setup Script

First, download the shell script from the GitHub repository:

```bash
# Download shell script directly from below link
curl -O https://raw.githubusercontent.com/last9/opentelemetry-examples/main/otel-collector/otel-operator/last9-otel-setup.sh
chmod +x last9-otel-setup.sh
```

### Installation Options

#### Option 1: Install Everything (Recommended)
```bash
./last9-otel-setup.sh endpoint="{{ .Logs.WriteURL }}" token="{{ .Logs.AuthValue }}" monitoring-endpoint="{{ .Metrics.WriteURL }}" username="{{ .Metrics.Username }}" password="{{ .Metrics.WriteToken }}"
```

#### Option 2: For Traces alone --> Install OpenTelemetry Operator and collector
```bash
./last9-otel-setup.sh operator-only endpoint="{{ .Logs.WriteURL }}" token="{{ .Logs.AuthValue }}"
```

#### Option 3: For Logs use case --> Install Only Collector for Logs (No Operator)
```bash
./last9-otel-setup.sh logs-only endpoint="{{ .Logs.WriteURL }}" token="{{ .Logs.AuthValue }}"
```

#### Option 4: Install Only Cluster Monitoring (Using Metrics)
```bash
./last9-otel-setup.sh monitoring-only monitoring-endpoint="{{ .Metrics.WriteURL }}" username="{{ .Metrics.Username }}" password="{{ .Metrics.WriteToken }}"
```


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
    # For Node.js apps use: inject-nodejs
    # For Python apps use: inject-python
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

### Uninstall Options

To remove all components (OpenTelemetry + Monitoring):

```bash
./last9-otel-setup.sh uninstall-all
```

---

## 🚀 Advanced Usage (Optional)

### Example 1: Set Custom Environment Name

Override the `deployment.environment` attribute to match your environment (production, staging, dev, etc.):

```bash
./last9-otel-setup.sh \
  endpoint="{{ .Logs.WriteURL }}" \
  token="{{ .Logs.AuthValue }}" \
  monitoring-endpoint="{{ .Metrics.WriteURL }}" \
  username="{{ .Metrics.Username }}" \
  password="{{ .Metrics.WriteToken }}" \
  env=production
```

### Example 2: Run on Nodes with Taints

If your Kubernetes nodes have taints (e.g., dedicated monitoring nodes), you need to provide tolerations:

#### Step 1: Create a tolerations YAML file

Create a file named `tolerations.yaml`:

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

#### Step 2: Run installation with tolerations

```bash
./last9-otel-setup.sh \
  endpoint="{{ .Logs.WriteURL }}" \
  token="{{ .Logs.AuthValue }}" \
  monitoring-endpoint="{{ .Metrics.WriteURL }}" \
  username="{{ .Metrics.Username }}" \
  password="{{ .Metrics.WriteToken }}" \
  tolerations-file=tolerations.yaml
```

**What it does:**
- Allows OpenTelemetry and monitoring components to run on tainted nodes

---
## 📚 Additional Resources

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Last9 Documentation](https://docs.last9.io/)
- [Individual Functions Usage Guide](INDIVIDUAL_FUNCTIONS_USAGE.md)
