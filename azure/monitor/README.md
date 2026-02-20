# Azure Monitor → Last9 with OpenTelemetry Collector

Collect Azure infrastructure metrics from Azure Monitor and send them to Last9 using OTel Collector — no Event Hub required.

## How it works

```
Azure Monitor REST API
    ↓  polls every 5 min (azuremonitorreceiver)
OTel Collector  ←  runs as a single pod in your AKS cluster
    ↓  OTLP/gRPC
Last9
```

Credentials stay entirely within your Azure environment. The collector polls Azure Monitor the same way Elastic's Metricbeat does — direct REST API, no streaming infrastructure.

## Prerequisites

- Azure subscription with resources to monitor
- Azure CLI (`az`) installed
- Docker or an existing AKS cluster
- Last9 account with OTLP credentials

## Quick Start

### 1. Create Azure Service Principal

```bash
chmod +x setup-azure-sp.sh
./setup-azure-sp.sh <your-subscription-id>
```

This creates a service principal with `Monitoring Reader` role only — read-only access to metrics, no write permissions to any resources.

### 2. Configure environment

```bash
cp .env.example .env
# Fill in values from setup-azure-sp.sh output + Last9 dashboard
```

Get Last9 OTLP credentials from: **Last9 console → Settings → Integrations → OTLP**

### 3. Run locally (Docker)

```bash
docker compose up
```

### 4. Deploy to AKS

```bash
kubectl create secret generic azure-monitor-collector \
  --from-env-file=.env

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-monitor-collector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-monitor-collector
  template:
    metadata:
      labels:
        app: azure-monitor-collector
    spec:
      containers:
        - name: collector
          image: otel/opentelemetry-collector-contrib:0.119.0
          args: ["--config=/etc/otel/config.yaml"]
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          envFrom:
            - secretRef:
                name: azure-monitor-collector
          volumeMounts:
            - name: config
              mountPath: /etc/otel
      volumes:
        - name: config
          configMap:
            name: azure-monitor-collector-config
EOF
```

## Configuration

| Variable | Description |
|----------|-------------|
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_CLIENT_ID` | Service principal client ID |
| `AZURE_CLIENT_SECRET` | Service principal client secret |
| `AZURE_RESOURCE_GROUP` | Resource group(s) to monitor |
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `LAST9_OTLP_HEADER` | Last9 authorization header |

### Tuning collection interval

Default is `300s` (5 min). For larger resource inventories, increase to reduce API calls:

| Resources | Recommended interval | API calls/day |
|-----------|---------------------|---------------|
| < 50 | 300s | ~14K |
| 50–100 | 300s + `use_batch_api: true` | ~14K (batched) |
| 100+ | Consider Event Hub via DCR | — |

### Filtering to specific Azure services

Uncomment and edit the `services` list in `collector-config.yaml`:

```yaml
services:
  - Microsoft.Compute/virtualMachines
  - Microsoft.ContainerService/managedClusters
  - Microsoft.Storage/storageAccounts
  - Microsoft.Web/sites
```

## Verification

Check collector health:
```bash
curl http://localhost:13133/
```

Check collector logs for successful scrapes:
```bash
docker compose logs -f
# look for: "Metrics exported" or "Sending metrics"
```

In Last9, metrics appear with the prefix matching the Azure resource type, e.g.:
- `azure_microsoft_compute_virtualmachines_*`
- `azure_microsoft_containerservice_managedclusters_*`

## Resources

- [azuremonitorreceiver (OTel Contrib)](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/azuremonitorreceiver/README.md)
- [Azure Monitor REST API limits](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/service-limits)
- [Last9 OTLP Integration](https://app.last9.io)
