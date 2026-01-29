# Tail-Based Sampling Deployment Examples

This folder contains deployment configurations for running the Node.js application with an OpenTelemetry Collector for tail-based sampling.

## Quick Reference

| Deployment | Collector Location | App Config |
|------------|-------------------|------------|
| PM2 | Docker container on same host | `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318` |
| Kubernetes | Deployment with Service | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4318` |
| Docker | Docker Compose service | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318` |
| Standalone | Systemd service | `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318` |

## Deployment Options

### PM2 (`pm2/`)

For Node.js apps managed by PM2. The collector runs as a Docker container.

```bash
# Start collector
./deployments/pm2/collector-setup.sh start

# Start app with PM2
pm2 start deployments/pm2/ecosystem.config.js
```

### Kubernetes (`kubernetes/`)

For Kubernetes clusters. Includes collector deployment, RBAC, and app configuration.

```bash
# Create namespace and secrets
kubectl create namespace observability
kubectl create secret generic last9-credentials \
  --from-literal=endpoint=https://otlp.last9.io \
  --from-literal=auth-header="Basic YOUR_TOKEN" \
  -n observability

# Deploy collector
kubectl apply -f deployments/kubernetes/otel-collector.yaml

# Deploy app
kubectl apply -f deployments/kubernetes/app-deployment.yaml
```

### Docker (`docker/`)

For Docker Compose environments. Full setup included.

```bash
export LAST9_OTLP_ENDPOINT=https://otlp.last9.io
export LAST9_AUTH_HEADER="Basic YOUR_TOKEN"

cd deployments/docker
docker-compose up -d
```

### Standalone (`standalone/`)

For bare-metal or VM deployments without containers. Installs collector as systemd service.

```bash
# Install collector (Linux with systemd)
sudo ./deployments/standalone/setup.sh install

# Edit credentials
sudo nano /etc/otel-collector/collector.env

# Restart collector
sudo systemctl restart otel-collector

# Run app
./deployments/standalone/run-app.sh
```

## Key Principle

**The application code is identical across all deployments.** Only these environment variables change:

| Variable | Direct Export | With Collector |
|----------|--------------|----------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otlp.last9.io` | `http://<collector>:4318` |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Basic TOKEN` | Not needed |
| `OTEL_TRACES_SAMPLER` | `parentbased_traceidratio` | `always_on` |

When using the collector:
- App sends 100% of traces to collector (`always_on`)
- Collector applies tail-based sampling (keeps errors, slow traces, 10% random)
- Collector exports sampled traces to Last9

## Customizing Sampling Policies

Edit `otel-collector-config.yaml` to adjust:

```yaml
tail_sampling:
  policies:
    - name: always_sample_errors
      type: status_code
      status_code:
        status_codes: [ERROR]

    - name: always_sample_slow
      type: latency
      latency:
        threshold_ms: 2000  # Adjust threshold

    - name: probabilistic_fallback
      type: probabilistic
      probabilistic:
        sampling_percentage: 10  # Adjust percentage
```

## Memory Considerations

Tail-based sampling holds traces in memory until `decision_wait` expires:

| Setting | Low Traffic | High Traffic |
|---------|-------------|--------------|
| `num_traces` | 100 | 500-1000 |
| `decision_wait` | 10s | 10s |
| `memory_limiter.limit_mib` | 400 | 1024+ |
