# OpenTelemetry Operator, Collector and Cluster monitoring Setup for kubernetes cluster

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


## 🚀 Quick Start - Single Command Deployment

## 🔧 Step 1: Deploy the OTEL Operator

### Step 1: Deploy Operator, Collector & Monitoring

#### 1.1: Download the Setup Script

First, copy the shell script from the GitHub repository to your local machine:

```bash
# Download shell script directly from below link
curl -O https://raw.githubusercontent.com/last9/opentelemetry-examples/otel-k8s-monitoring/otel-collector/otel-operator/java/k8s/setup-otel.sh
chmod +x setup-otel.sh
```

#### 1.2: Run the Installation

Execute the script to install everything:


```bash
./setup-otel.sh token="your-token-here" monitoring=true cluster="your-cluster-name" username="your-username" password="your-password"
=======

**What this script installs:**
- ✅ OpenTelemetry Operator (Helm chart: `opentelemetry-operator`)
- ✅ OpenTelemetry Collector (Helm chart: `last9-opentelemetry-collector`)
- ✅ Collector Service (Kubernetes service)
- ✅ Common Instrumentation (Auto-instrumentation configuration)
- ✅ Last9 Monitoring Stack (Helm chart: `last9-k8s-monitoring`)
- ✅ Prometheus with Last9 remote write configuration
- ✅ kube-state-metrics and node-exporter
- ✅ Last9 remote write secret
- ✅ Helm repositories setup (open-telemetry + prometheus-community)
- ✅ Namespace creation (`last9`)

### Installation Options

#### Option 1: Install Everything (Recommended)
```bash
./setup-otel.sh token="your-token-here" monitoring=true cluster="your-cluster-name" username="your-username" password="your-password"
```

#### Option 2: Install Only OpenTelemetry Operator and Collector (No Monitoring)
```bash
./setup-otel.sh token="your-token-here"
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


### Uninstall Options

To remove all components (OpenTelemetry + Monitoring):

```bash
./setup-otel.sh uninstall-all
```

To remove only monitoring components:

```bash
./setup-otel.sh uninstall function="uninstall_last9_monitoring"
```

## 📚 Additional Resources

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Last9 Documentation](https://docs.last9.io/)
- [Individual Functions Usage Guide](INDIVIDUAL_FUNCTIONS_USAGE.md)

