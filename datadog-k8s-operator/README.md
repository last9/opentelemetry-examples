# Migrating from Datadog K8s Operator to OpenTelemetry for Logs

This guide provides comprehensive examples for migrating log processing rules from Datadog Kubernetes Operator to OpenTelemetry Collector with Last9.

## Overview

Datadog uses the **DatadogAgent CRD** and **pod annotations** for log collection and processing. OpenTelemetry uses the **OTel Collector** with **processors** for equivalent functionality.

### Key Mapping

| Datadog Feature | OpenTelemetry Equivalent |
|-----------------|-------------------------|
| `exclude_at_match` | `filter` processor with OTTL |
| `include_at_match` | `filter` processor (negated condition) |
| `mask_sequences` | `transform` processor with `replace_pattern` |
| `multi_line` | `recombine` operator in filelog receiver |
| `DD_CONTAINER_EXCLUDE_LOGS` | `filter` processor on resource attributes |
| Pod annotations | Collector config (centralized) |
| JSON auto-parsing | `json_parser` operator |
| Grok Parser (cloud) | `regex_parser` operator |
| Vector VRL transforms | `transform` processor with OTTL |

## Quick Start

### 1. Install Last9 OTel Collector

```bash
# Download the setup script
curl -O https://raw.githubusercontent.com/last9/l9-otel-operator/main/last9-otel-setup.sh
chmod +x last9-otel-setup.sh

# Install with logs collection
./last9-otel-setup.sh logs-only \
  endpoint="YOUR_LAST9_OTLP_ENDPOINT" \
  token="YOUR_AUTH_TOKEN"
```

### 2. Apply Custom Processing Rules

Add processors to the collector ConfigMap based on your needs. See the [migration examples](#migration-examples) below.

## Directory Structure

```
datadog-k8s-operator/
├── README.md                          # This file
├── datadog-reference/
│   ├── datadog-agent-crd.yaml        # Sample DatadogAgent v2alpha1 CRD
│   ├── pod-annotations.yaml          # Pod annotation patterns
│   ├── helm-values.yaml              # Helm chart with processing rules
│   └── vector-pipeline.toml          # Observability Pipelines (Vector)
├── otel-collector/
│   ├── collector-config.yaml         # Complete OTel Collector config
│   ├── collector-daemonset.yaml      # K8s DaemonSet manifest
│   └── collector-configmap.yaml      # ConfigMap for collector
├── migration-examples/
│   ├── 01-healthcheck-exclusion/     # Drop health check logs
│   ├── 02-pii-masking/               # Redact sensitive data
│   ├── 03-severity-filtering/        # Keep only errors/warnings
│   ├── 04-namespace-exclusion/       # Exclude system namespaces
│   ├── 05-pattern-filtering/         # Custom pattern filtering
│   ├── 06-multiline-logs/            # Multi-line log aggregation
│   ├── 07-json-parsing/              # JSON log parsing
│   ├── 08-grok-parsing/              # Grok/regex parsing
│   └── 09-vrl-transforms/            # VRL to OTTL migration
└── quick-reference/
    └── cheatsheet.md                 # Side-by-side quick reference
```

## Migration Examples

### 1. Health Check Exclusion

**Datadog** uses `exclude_at_match` to drop health check logs:
```yaml
log_processing_rules:
  - type: exclude_at_match
    name: exclude_healthcheck
    pattern: "GET /health"
```

**OpenTelemetry** uses the `filter` processor:
```yaml
processors:
  filter/healthcheck:
    error_mode: ignore
    logs:
      log_record:
        - 'IsMatch(body, "GET /health.*")'
```

[See full example](./migration-examples/01-healthcheck-exclusion/)

### 2. PII Masking

**Datadog** uses `mask_sequences` to redact sensitive data:
```yaml
log_processing_rules:
  - type: mask_sequences
    name: mask_ssn
    pattern: "\\d{3}-\\d{2}-\\d{4}"
    replace_placeholder: "[SSN_REDACTED]"
```

**OpenTelemetry** uses the `transform` processor:
```yaml
processors:
  transform/pii:
    error_mode: ignore
    log_statements:
      - context: log
        statements:
          - replace_pattern(body, "\\d{3}-\\d{2}-\\d{4}", "[SSN_REDACTED]")
```

[See full example](./migration-examples/02-pii-masking/)

### 3. Severity Filtering

**Datadog** uses `include_at_match` to keep only important logs:
```yaml
log_processing_rules:
  - type: include_at_match
    name: only_errors
    pattern: "(ERROR|WARN|FATAL)"
```

**OpenTelemetry** uses severity-based filtering:
```yaml
processors:
  filter/severity:
    error_mode: ignore
    logs:
      log_record:
        - 'severity_number < SEVERITY_NUMBER_WARN'
```

[See full example](./migration-examples/03-severity-filtering/)

### 4. Namespace Exclusion

**Datadog** uses environment variables:
```yaml
DD_CONTAINER_EXCLUDE_LOGS: "kube_namespace:kube-system"
```

**OpenTelemetry** uses resource attribute filtering:
```yaml
processors:
  filter/namespace:
    error_mode: ignore
    logs:
      log_record:
        - 'resource.attributes["k8s.namespace.name"] == "kube-system"'
```

[See full example](./migration-examples/04-namespace-exclusion/)

### 5. Pattern Filtering

**Datadog** drops logs matching custom patterns:
```yaml
log_processing_rules:
  - type: exclude_at_match
    name: exclude_debug
    pattern: "^\\[DEBUG\\]"
```

**OpenTelemetry** equivalent:
```yaml
processors:
  filter/patterns:
    error_mode: ignore
    logs:
      log_record:
        - 'IsMatch(body, "^\\[DEBUG\\]")'
```

[See full example](./migration-examples/05-pattern-filtering/)

### 6. Multi-line Log Aggregation

**Datadog** uses `multi_line` to aggregate stack traces:
```yaml
log_processing_rules:
  - type: multi_line
    name: java_stacktrace
    pattern: "^\\d{4}-\\d{2}-\\d{2}"
```

**OpenTelemetry** uses the `recombine` operator:
```yaml
receivers:
  filelog:
    operators:
      - type: recombine
        combine_field: body
        is_first_entry: body matches "^\\d{4}-\\d{2}-\\d{2}"
        source_identifier: attributes["log.file.path"]
```

[See full example](./migration-examples/06-multiline-logs/)

### 7. JSON Parsing

**Datadog** auto-detects and parses JSON logs.

**OpenTelemetry** uses the `json_parser` operator:
```yaml
receivers:
  filelog:
    operators:
      - type: json_parser
        parse_from: attributes.log
        parse_to: attributes
```

[See full example](./migration-examples/07-json-parsing/)

### 8. Grok/Regex Parsing

**Datadog** uses cloud-side Grok Parser in Log Pipelines:
```
%{IPORHOST:client_ip} %{NOTSPACE} \[%{HTTPDATE:timestamp}\] "%{WORD:method} %{NOTSPACE:path}"
```

**OpenTelemetry** uses `regex_parser` with named capture groups:
```yaml
receivers:
  filelog:
    operators:
      - type: regex_parser
        regex: '^(?P<client_ip>[^ ]+) [^ ]+ \[(?P<timestamp>[^\]]+)\] "(?P<method>\w+) (?P<path>[^ ]+)"'
```

[See full example](./migration-examples/08-grok-parsing/)

### 9. VRL Transforms

**Vector/VRL** provides advanced transformations in Datadog Observability Pipelines:
```toml
[transforms.process]
type = "remap"
source = '''
  del(.password)
  .level = upcase(.level)
  if match(.message, r'error') { .alert = true }
'''
```

**OpenTelemetry OTTL** equivalent:
```yaml
processors:
  transform/vrl_equiv:
    log_statements:
      - context: log
        statements:
          - delete_key(attributes, "password")
          - set(attributes["level"], ConvertCase(attributes["level"], "upper"))
          - set(attributes["alert"], true) where IsMatch(body, "(?i)error")
```

[See full example](./migration-examples/09-vrl-transforms/)

## Architecture Comparison

### Datadog Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  DatadogAgent CRD                    │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ Node Agent  │  │ Node Agent  │  │ Node Agent  │ │   │
│  │  │ (DaemonSet) │  │ (DaemonSet) │  │ (DaemonSet) │ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │   │
│  │         │                │                │         │   │
│  │         └────────────────┼────────────────┘         │   │
│  │                          │                          │   │
│  │              ┌───────────▼───────────┐             │   │
│  │              │  log_processing_rules │             │   │
│  │              │  - exclude_at_match   │             │   │
│  │              │  - include_at_match   │             │   │
│  │              │  - mask_sequences     │             │   │
│  │              └───────────┬───────────┘             │   │
│  └──────────────────────────┼──────────────────────────┘   │
│                             │                              │
└─────────────────────────────┼──────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   Datadog SaaS   │
                    └─────────────────┘
```

### OpenTelemetry Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │               OTel Collector (DaemonSet)             │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │  Collector  │  │  Collector  │  │  Collector  │ │   │
│  │  │   (Node 1)  │  │   (Node 2)  │  │   (Node 3)  │ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │   │
│  │         │                │                │         │   │
│  │         └────────────────┼────────────────┘         │   │
│  │                          │                          │   │
│  │              ┌───────────▼───────────┐             │   │
│  │              │      Processors       │             │   │
│  │              │  - filter             │             │   │
│  │              │  - transform          │             │   │
│  │              │  - k8sattributes      │             │   │
│  │              │  - batch              │             │   │
│  │              └───────────┬───────────┘             │   │
│  └──────────────────────────┼──────────────────────────┘   │
│                             │                              │
└─────────────────────────────┼──────────────────────────────┘
                              │ OTLP/HTTPS
                              ▼
                    ┌─────────────────┐
                    │      Last9      │
                    └─────────────────┘
```

## Key Differences

| Aspect | Datadog | OpenTelemetry |
|--------|---------|---------------|
| **Configuration** | Pod annotations + Agent env vars | Collector ConfigMap (centralized) |
| **Language** | Golang regex | OTTL + regex |
| **Processing** | Agent-level (per node) | Collector-level (pipeline) |
| **Scope** | Per-container or global | Pipeline-level |
| **Flexibility** | Fixed rule types | Programmable with OTTL |

## Processor Order (Important!)

The order of processors in the pipeline matters. Recommended order:

```yaml
service:
  pipelines:
    logs:
      receivers: [filelog, otlp]
      processors:
        - memory_limiter       # 1. Prevent OOM (always first)
        - k8sattributes        # 2. Add K8s metadata
        - filter/namespace     # 3. Drop unwanted namespaces (early = less processing)
        - filter/healthcheck   # 4. Drop noise
        - filter/severity      # 5. Drop by severity
        - transform/pii        # 6. Mask sensitive data
        - transform/enrich     # 7. Add custom attributes
        - batch                # 8. Batch for efficiency (always last before export)
      exporters: [otlp/last9]
```

## Testing Your Migration

1. **Enable debug exporter** temporarily:
```yaml
exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    logs:
      exporters: [debug, otlp/last9]
```

2. **Check collector logs**:
```bash
kubectl logs -n last9 -l app.kubernetes.io/name=last9-otel-collector -f
```

3. **Verify in Last9**:
- Check that logs appear in Last9 dashboard
- Verify sensitive data is masked
- Confirm unwanted logs are filtered

## Common Migration Scenarios

### Scenario 1: Multiple Processing Rules

**Datadog** (sequential rules):
```yaml
log_processing_rules:
  - type: exclude_at_match
    name: exclude_health
    pattern: "GET /health"
  - type: mask_sequences
    name: mask_email
    pattern: "[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}"
    replace_placeholder: "[EMAIL]"
```

**OpenTelemetry** (multiple processors):
```yaml
processors:
  filter/health:
    logs:
      log_record:
        - 'IsMatch(body, "GET /health")'

  transform/mask:
    log_statements:
      - context: log
        statements:
          - replace_pattern(body, "[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}", "[EMAIL]")

service:
  pipelines:
    logs:
      processors: [filter/health, transform/mask, batch]
```

### Scenario 2: Conditional Processing

**Datadog** (per-container via annotation):
```yaml
ad.datadoghq.com/nginx.logs: |
  [{
    "source": "nginx",
    "log_processing_rules": [{
      "type": "exclude_at_match",
      "name": "exclude_static",
      "pattern": "\\.(css|js|png|jpg)"
    }]
  }]
```

**OpenTelemetry** (conditional in transform):
```yaml
processors:
  filter/nginx_static:
    logs:
      log_record:
        - 'resource.attributes["k8s.container.name"] == "nginx" and IsMatch(body, "\\.(css|js|png|jpg)")'
```

## Resources

### OpenTelemetry Documentation

**Processors**:
- [Filter Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/filterprocessor)
- [Transform Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/transformprocessor)
- [Attributes Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/attributesprocessor)

**OTTL (OpenTelemetry Transformation Language)**:
- [OTTL Functions](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/pkg/ottl/ottlfuncs)
- [OTTL Contexts](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/ottl/contexts/README.md)

**Filelog Receiver Operators**:
- [Operators Overview](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/README.md)
- [Recombine Operator](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/recombine.md)
- [JSON Parser](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/json_parser.md)
- [Regex Parser](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/regex_parser.md)

### Datadog Documentation
- [Log Processing Rules](https://docs.datadoghq.com/agent/logs/advanced_log_collection/)
- [Datadog Operator](https://docs.datadoghq.com/containers/kubernetes/installation/?tab=operator)

### Last9
- [Last9 Documentation](https://docs.last9.io/)

## Support

For questions about this migration guide:
- Open an issue in this repository
- Contact Last9 support at support@last9.io
