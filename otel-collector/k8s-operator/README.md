# Python Log Writer Example (Minikube)

This project demonstrates a simple Python application that continuously writes log entries to `/log/app.log` inside a container. The app is containerized with Docker and can be deployed to a Minikube Kubernetes cluster. It also demonstrates how to collect these logs using an OpenTelemetry Collector sidecar (manual, no operator required).

---

## ⚠️ Important Caveat: Do Not Mount Volumes at `/code`

**Never mount a Kubernetes volume (such as `emptyDir`) at the same path as your application code (e.g., `/code`).**

- If you mount a volume at `/code`, it will override the `/code` directory from your image, and your app will fail to start with:
  ```
  python: can't open file '/code/app.py': [Errno 2] No such file or directory
  ```
- **Best practice:**
  - Keep your code in `/code` (from the image, no volume mount).
  - Write logs to `/log` (mount a shared `emptyDir` volume at `/log` in both the app and sidecar containers).

---

## How to Enable Log Collection with a Sidecar (Step-by-Step)

### 1. **Update Your App to Write Logs to `/log`**

Change your log path in your app code:

```python
import os
import time

def continuous_log_writer():
    os.makedirs('/log', exist_ok=True)
    with open('/log/app.log', 'a') as f:
        while True:
            f.write(f"Log entry at {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.flush()
            time.sleep(1)

if __name__ == "__main__":
    continuous_log_writer()
```

### 2. **Update Your Dockerfile (no change needed for log path)**

Just ensure your Dockerfile does not mount anything at `/code`:

```dockerfile
FROM python:3.11-slim
WORKDIR /code
COPY app.py /code/app.py
CMD ["python", "/code/app.py"]
```

### 3. **Update Your Deployment to Mount `/log`**

Add a shared `emptyDir` volume at `/log` for both containers:

```yaml
spec:
  containers:
    - name: python-log-writer
      ...
      volumeMounts:
        - name: log-volume
          mountPath: /log
    - name: otel-collector
      ...
      volumeMounts:
        - name: log-volume
          mountPath: /log
        - name: otelcol-config
          mountPath: /etc/otelcol-config.yaml
          subPath: otelcol-config.yaml
  volumes:
    - name: log-volume
      emptyDir: {}
    - name: otelcol-config
      configMap:
        name: otelcol-config
```

### 4. **Create the OpenTelemetry Collector ConfigMap**

Create a file named `otelcol-config.yaml`:

```yaml
receivers:
  filelog:
    include: [ /log/*.log ]
    start_at: beginning
processors:
  batch: {}
exporters:
  debug:
    verbosity: detailed
service:
  pipelines:
    logs:
      receivers: [filelog]
      processors: [batch]
      exporters: [debug]
```

Create the ConfigMap:

```
kubectl create configmap otelcol-config --from-file=otelcol-config.yaml
```

### 5. **Build and Deploy**

1. **Build the Docker image inside Minikube:**
   ```sh
   eval $(minikube docker-env)
   docker build -t python-log-writer:latest .
   ```
2. **Apply the deployment:**
   ```sh
   kubectl apply -f k8s-app.yaml
   ```

### 6. **Verify**

- Check pod status:
  ```sh
  kubectl get pods -l app=python-log-writer
  ```
- Check app logs:
  ```sh
  kubectl exec -it <pod-name> -c python-log-writer -- tail -f /log/app.log
  ```
- Check collector logs:
  ```sh
  kubectl logs <pod-name> -c otel-collector
  ```

---

## Prerequisites
- Docker
- Minikube installed and running
- kubectl configured to access your Minikube cluster

## 1. Start Minikube

If Minikube is not already running, start it:

```
minikube start
```

## 2. Build the Docker Image Inside Minikube

To make the image available to your Minikube cluster, build it using Minikube's Docker daemon:

```
eval $(minikube docker-env)
docker build -t python-log-writer:latest .
```

## 3. Create the OpenTelemetry Collector ConfigMap

Create a file named `otelcol-config.yaml` with the following content:

```
receivers:
  filelog:
    include: [ /log/*.log ]
    start_at: beginning
processors:
  batch: {}
exporters:
  debug:
    verbosity: detailed
service:
  pipelines:
    logs:
      receivers: [filelog]
      processors: [batch]
      exporters: [debug]
```

Create the ConfigMap in your cluster:

```
kubectl create configmap otelcol-config --from-file=otelcol-config.yaml
```

## 4. Deploy to Minikube (with manual sidecar)

Apply the deployment manifest:

```
kubectl apply -f k8s-app.yaml
```

## 5. Verify the Deployment

Check the pod status:

```
kubectl get pods -l app=python-log-writer
```

View logs (the app writes to a file, not stdout):

```
kubectl exec -it <pod-name> -c python-log-writer -- tail -f /log/app.log
```

Check the OpenTelemetry Collector sidecar logs:

```
kubectl logs <pod-name> -c otel-collector
```

Replace `<pod-name>` with the actual pod name from the previous command.

## Cleanup

To remove the deployment and configmap:

```
kubectl delete -f k8s-app.yaml
kubectl delete configmap otelcol-config
```

## (Optional) Minikube Dashboard

To open the Minikube dashboard for a visual overview:

```
minikube dashboard
``` 