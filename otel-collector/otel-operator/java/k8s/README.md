# 🚀 OpenTelemetry Operator Example for Java Apps

This example demonstrates how to use the OpenTelemetry (OTEL) Operator to enable **auto-instrumentation** for a Java application running in Kubernetes.

## 📋 Prerequisites

- Kubernetes cluster running
- `kubectl` configured and connected to your cluster
- `helm` installed on your system
- Java application ready for deployment

## 📁 Repository Setup

> **💡 Tip**: Clone this repository to your local machine for easy access to YAML files and reference during setup.

```sh
git clone <repository-url>
cd opentelemetry-examples/otel-collector/otel-operator/java/k8s
```

## 🔧 Step 1: Deploy the OTEL Operator

Install the OpenTelemetry Operator using Helm:

```sh
# Add the OpenTelemetry Helm repository
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Install the operator with optimized settings
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
--set "manager.collectorImage.repository=ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s" \
--set admissionWebhooks.certManager.enabled=false \
--set admissionWebhooks.autoGenerateCert.enabled=true
```

> **✅ Verification**: Check if the operator is running:
> ```sh
> kubectl get pods -n <your-namespace> | grep opentelemetry-operator
> ```

<details>
<summary>🗑️ Uninstall Instructions</summary>

To remove the operator:

```sh
helm uninstall opentelemetry-operator
```
</details>

---

## 📊 Step 2: Deploy the OpenTelemetry Collector

The OpenTelemetry Collector acts as a central hub for receiving, processing, and exporting telemetry data.

### Configuration

1. **Open** the `OpenTelemetryCollector.yaml` file in this directory
2. **Replace** the placeholder token with your actual Last9 token or configuration
3. **Apply** the configuration to your namespace where the Java app is running:

```sh
kubectl apply -f OpenTelemetryCollector.yaml -n <your-namespace>
```

> **✅ Verification**: Check if the collector is running:
> ```sh
> kubectl get pods -n <your-namespace> | grep otel-collector
> ```

---

## 🎯 Step 3: Create the Instrumentation Object

The Instrumentation object defines how your Java application should be automatically instrumented.

### Setup

1. **Use** the provided `instrumentation.yaml` file (no changes needed)
2. **Apply** it to your namespace where the Java app is running:

```sh
kubectl apply -f instrumentation.yaml -n <your-namespace>
```

> **✅ Verification**: Check if the instrumentation is created:
> ```sh
> kubectl get instrumentation -n <your-namespace>
> ```

---

## 🏷️ Step 4: Annotate Your Application Deployment

This is the **key step** that enables auto-instrumentation for your Java application.

### Add Annotation

Add this annotation to your deployment's pod template metadata:

```yaml
annotations:
  instrumentation.opentelemetry.io/inject-java: "true"
```

### Example Reference

See the example in `deploy.yaml` file (lines 16-17):

```yaml
metadata:
  labels:
    app: spring-boot-app
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"  # ← This line enables auto-instrumentation
```

### Apply Your Deployment

```sh
kubectl apply -f deploy.yaml -n <your-namespace>
```

> **💡 Pro Tip**: The annotation tells the OpenTelemetry Operator to automatically inject the Java agent into your application pods.

---

## ✅ Validation & Verification

### Check All Components

Verify that all components are running correctly:

```sh
# Check operator status
kubectl get pods -n de <your-namespace> | grep opentelemetry-operator

# Check collector status
kubectl get pods -n <your-namespace> | grep otel-collector

# Check instrumentation object
kubectl get instrumentation -n <your-namespace>

# Check your application deployment
kubectl get pods -n <your-namespace> | grep <your-app-name>
```

### Expected Behavior

✅ **Success Indicators:**
- All pods are in `Running` state
- No error messages in pod logs
- Your Java application should be automatically instrumented
- Telemetry data flows through the OTEL Collector to Last9

### Troubleshooting

If you encounter issues:

1. **Check pod logs**: `kubectl logs <pod-name> -n <namespace>`
2. **Verify annotations**: Ensure the annotation is correctly applied
3. **Check operator logs**: `kubectl logs -l app.kubernetes.io/name=opentelemetry-operator -n default`

---

## 🎉 Success!

Once all steps are completed successfully, your Java application will be automatically instrumented and sending telemetry data to Last9 via the OpenTelemetry Collector.
