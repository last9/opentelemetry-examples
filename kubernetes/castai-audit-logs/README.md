# CAST AI Audit Logs → Last9

Ship CAST AI audit logs to Last9 via the [`audit-logs-receiver`](https://github.com/castai/audit-logs-receiver) custom OpenTelemetry Collector and the OTLP HTTP exporter.

## Prerequisites

- Kubernetes cluster with `kubectl` access
- Helm v3.14+
- CAST AI API key with **Audit Log read** scope ([docs](https://docs.cast.ai/docs/authentication#obtaining-api-access-key))
- CAST AI cluster ID (optional — filters events to one cluster)
- Last9 OTLP credentials from [Integrations → OpenTelemetry](https://app.last9.io/integrations?integration=OpenTelemetry)

## Quick Start

```bash
helm repo add castai-helm https://castai.github.io/helm-charts
helm repo update castai-helm

helm install audit-logs castai-helm/castai-audit-logs-receiver \
  --namespace castai-logs --create-namespace \
  --set castai.apiKey="$CASTAI_API_KEY" \
  --set castai.clusterID="$CASTAI_CLUSTER_ID" \
  --set-string "config.exporters.otlphttp/last9.headers.Authorization=$LAST9_OTLP_AUTH" \
  --values values.yaml
```

Replace the secret values with your own (use `.env.example` as template).

## What the config does

The CAST AI receiver emits each audit event as an OTel `LogRecord` with all fields stored as `Attributes` — `body`, `service.name`, and `Timestamp` need explicit handling:

| Fix | Why |
|-----|-----|
| `set(body, String(attributes["event"]))` | Receiver leaves body empty. Last9 needs body populated for indexing. |
| `delete_key(attributes, "event")` | Avoid duplicating the event payload in both body and attributes. |
| `set(time, observed_time)` | Receiver sets `Timestamp` to the audit event's original time, which may fall outside recent-time query windows in Last9. Override to ingestion time. |
| `service.name` upsert on resource | Receiver does not set `service.name`. Without this, records are unindexed by service. |
| `encoding: json` on exporter | OTLP/HTTP defaults to protobuf; JSON encoding is used here to match the payload shape confirmed working against Last9. |

## Verification

```bash
kubectl logs -n castai-logs audit-logs-castai-audit-logs-receiver-0 --tail=50
```

Look for `processing new audit log` entries. Then query Last9:

```
service.name = "castai-audit-logs"
```

Trigger an audit event by creating/updating resources in your CAST AI cluster — e.g., `clusterConnected`, `agentDisconnected`, or configuration changes.

## Uninstall

```bash
helm uninstall audit-logs -n castai-logs
kubectl delete namespace castai-logs
```

## References

- [CAST AI audit-logs-receiver](https://github.com/castai/audit-logs-receiver)
- [CAST AI audit log docs](https://docs.cast.ai/docs/audit-log-exporter)
- [Last9 OpenTelemetry integration](https://last9.io/docs/integrations/opentelemetry/)
