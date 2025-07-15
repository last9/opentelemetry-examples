# OpenTelemetry Operator Example for Java Apps

This example demonstrates how to use the OpenTelemetry (OTEL) Operator to enable auto-instrumentation for a Java application running in Kubernetes.

---

## Step 1: Deploy the OTEL Operator

Follow the official documentation to deploy the OTEL Operator using the Helm chart in your Kubernetes cluster:

[OpenTelemetry Operator Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-operator#opentelemetry-operator-helm-chart)

---

## Step 2: Deploy the OpenTelemetry Collector

Create a Kubernetes object to deploy the OTEL Collector. 

- Open the `OpenTelemetryCollector.yaml` file in this directory.
- Replace the placeholder token with your actual token or configuration as needed.
- Apply the file to your desired namespace:

```sh
kubectl apply -f OpenTelemetryCollector.yaml -n <your-namespace>
```

---

## Step 3: Create the Instrumentation Object

Create an `Instrumentation` object to enable auto-instrumentation for your Java apps.

- Use the provided `instrumentation.yaml` file.
- Apply it to your namespace:

```sh
kubectl apply -f instrumentation.yaml -n <your-namespace>
```

---

## Step 4: Annotate Your Application Deployment

After confirming that the above resources have been created successfully, add the required annotation to your application's `Deployment` YAML file. This annotation enables auto-instrumentation for your app.

Refer to the official documentation for the correct annotation for your language and use case:

[Add Annotations to Existing Deployments](https://opentelemetry.io/docs/platforms/kubernetes/operator/automatic/#add-annotations-to-existing-deployments)

---

## Validation

- Ensure all objects (`OpenTelemetryCollector`, `Instrumentation`, and your annotated `Deployment`) are created without errors.
- Once annotated, your Java application should be automatically instrumented and sending telemetry data via the OTEL Collector to Last9.
