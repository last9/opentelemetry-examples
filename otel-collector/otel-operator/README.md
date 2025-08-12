# OpenTelemetry Operator, Collector and Cluster Monitoring Setup for Kubernetes

This guide shows you how to deploy OpenTelemetry Operator, Collector, and Cluster Monitoring in a single step using our automated setup script.

## 📋 Prerequisites

Before running the script, ensure you have:

- ✅ **Kubernetes Cluster**: A running Kubernetes cluster
- ✅ **kubectl**: Configured and connected to your cluster
- ✅ **helm**: Installed (v3.9+)
- ✅ **git**: Installed
- ✅ **Last9 Token**: https://app.last9.io/integrations?category=all&search_term=op&integration=OpenTelemetry --> Copy the Auth header token
- ✅ **Last9 Username**: https://app.last9.io/v2/organizations/last9/integrations?cluster=bf853555-4dc3-4f30-82da-bfcdae575c7b&category=all&search_term=prome&integration=Prometheus --> Copy the username value
- ✅ **Last9 Password**: https://app.last9.io/v2/organizations/last9/integrations?cluster=bf853555-4dc3-4f30-82da-bfcdae575c7b&category=all&search_term=prome&integration=Prometheus  --> Copy the password value


### Step 1 Quick Start - Installation Options

### Download the Setup Script

First, download the shell script from the GitHub repository:

```bash
# Download shell script directly from below link
curl -O https://raw.githubusercontent.com/last9/opentelemetry-examples/otel-k8s-monitoring/otel-collector/otel-operator/last9-otel-setup.sh
chmod +x last9-otel-setup.sh
```

### Installation Options

#### Option 1: Install Everything (Recommended - This will cover integration of Logs, Traces and Cluster Monitoring)
```bash
./last9-otel-setup.sh token="your-token-here" username="your-username" password="your-password"
```

#### Option 2: For Traces alone --> Install OpenTelemetry Operator and collector
```bash
./last9-otel-setup.sh operator-only token="your-token-here"
```

#### Option 3: For Logs use case --> Install Only Collector for Logs (No Operator)
```bash
./last9-otel-setup.sh logs-only token="your-token-here"
```

#### Option 4: Install Only Cluster Monitoring (Using Metrics)
```bash
./last9-otel-setup.sh monitoring-only username="your-username" password="your-password"
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

### In case, you want to Uninstall any or all of components, use below

```bash
./last9-otel-setup.sh uninstall-all
```

## 📚 Additional Resources

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Last9 Documentation](https://docs.last9.io/)
- [Individual Functions Usage Guide](INDIVIDUAL_FUNCTIONS_USAGE.md)

