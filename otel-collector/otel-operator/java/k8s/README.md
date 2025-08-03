# OpenTelemetry Operator & Collector Setup

This guide shows you how to deploy OpenTelemetry Operator and Collector in a single step using our automated setup script.

## 📋 Prerequisites

Before running the script, ensure you have:

- ✅ **Kubernetes Cluster**: A running Kubernetes cluster
- ✅ **kubectl**: Configured and connected to your cluster
- ✅ **helm**: Installed (v3.9+)
- ✅ **git**: Installed
- ✅ **Last9 Token**: get authentication token for Last9 (To generate the token, login to last9 platform then --> integration --> Search Opentelemetary --> Connect --> You will see Auth header in the doc just copy Token alone)


## 🚀 Quick Start - Single Command Deployment

### Step 1: Deploy Operator & Collector

Run this single command to install everything:

```bash
./setup-otel.sh token="your-token-here"
```

**What this script installs:**
- ✅ OpenTelemetry Operator (Helm chart: `opentelemetry-operator`)
- ✅ OpenTelemetry Collector (Helm chart: `last9-opentelemetry-collector`)
- ✅ Collector Service (Kubernetes service)
- ✅ Common Instrumentation (Auto-instrumentation configuration)
- ✅ Helm repositories setup
- ✅ Namespace creation (`last9`)



### Step 2: Verify Installation

Check that all pods are up and running:

```bash
# Check pods
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



## 🔧 Advanced Usage

### Individual Function Execution

You can also run specific components individually:

```bash
# Install operator only
./setup-otel.sh function="install_operator" 

# Install collector with custom values
./setup-otel.sh function="install_collector" token="your-token" values="custom-values.yaml"

# Verify installation
./setup-otel.sh function="verify_installation"
```

### Custom Values File

Use your own values file instead of the default:

```bash
./setup-otel.sh function="install_collector" token="your-token" values="my-custom-values.yaml"
```

**Note:** The values file should be in your current directory. When using a custom values file, no token replacement is performed - use the file as-is.

### Uninstall Everything

To remove all OpenTelemetry components:

```bash
./setup-otel.sh uninstall
```


## 📝 Configuration Files

The script uses these configuration files from the repository:

- `last9-otel-collector-values.yaml` - Collector configuration
- `collector-svc.yaml` - Collector service definition
- `instrumentation.yaml` - Auto-instrumentation configuration


## 📚 Additional Resources

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Last9 Documentation](https://docs.last9.io/)
- [Individual Functions Usage Guide](INDIVIDUAL_FUNCTIONS_USAGE.md)

