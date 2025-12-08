# Datadog to OpenTelemetry Migration Cheatsheet

Quick reference for migrating log processing rules from Datadog K8s Operator to OpenTelemetry Collector.

## Rule Type Mapping

| Datadog | OpenTelemetry | Processor/Operator |
|---------|---------------|-----------|
| `exclude_at_match` | Drop logs matching pattern | `filter` processor |
| `include_at_match` | Keep only matching (drop non-matching) | `filter` with `not` |
| `mask_sequences` | Replace pattern with placeholder | `transform` with `replace_pattern` |
| `multi_line` | Aggregate multi-line logs | `recombine` operator |
| `DD_CONTAINER_EXCLUDE_LOGS` | Filter by resource attributes | `filter` on `k8s.namespace.name` |
| `DD_CONTAINER_INCLUDE_LOGS` | Complex routing | `filter` with negated conditions |
| JSON auto-parsing | Parse JSON logs | `json_parser` operator |
| Grok Parser (cloud) | Parse with regex | `regex_parser` operator |
| VRL `del()` | Delete field | OTTL `delete_key()` |
| VRL `abort` | Drop log | `filter` processor |
| VRL `replace()` | Replace pattern | OTTL `replace_pattern()` |

---

## 1. Health Check Exclusion

### Datadog
```yaml
ad.datadoghq.com/nginx.logs: |
  [{
    "log_processing_rules": [{
      "type": "exclude_at_match",
      "name": "exclude_health",
      "pattern": "GET /health"
    }]
  }]
```

### OpenTelemetry
```yaml
processors:
  filter/healthcheck:
    logs:
      log_record:
        - 'IsMatch(body, "GET /health.*")'
```

---

## 2. PII Masking

### Datadog
```yaml
log_processing_rules:
  - type: mask_sequences
    name: mask_ssn
    pattern: "\\d{3}-\\d{2}-\\d{4}"
    replace_placeholder: "[SSN]"
```

### OpenTelemetry
```yaml
processors:
  transform/pii:
    log_statements:
      - context: log
        statements:
          - replace_pattern(body, "\\d{3}-\\d{2}-\\d{4}", "[SSN]")
```

---

## 3. Severity Filtering

### Datadog (keep errors only)
```yaml
log_processing_rules:
  - type: include_at_match
    name: only_errors
    pattern: "(ERROR|FATAL)"
```

### OpenTelemetry
```yaml
processors:
  filter/severity:
    logs:
      log_record:
        - 'severity_number < SEVERITY_NUMBER_ERROR'
```

### OpenTelemetry (drop DEBUG)
```yaml
processors:
  filter/debug:
    logs:
      log_record:
        - 'IsMatch(body, ".*level=debug.*")'
```

---

## 4. Namespace Exclusion

### Datadog
```yaml
DD_CONTAINER_EXCLUDE_LOGS: "kube_namespace:kube-system"
```

### OpenTelemetry
```yaml
processors:
  filter/namespace:
    logs:
      log_record:
        - 'resource.attributes["k8s.namespace.name"] == "kube-system"'
```

---

## 5. Pattern Filtering

### Datadog
```yaml
log_processing_rules:
  - type: exclude_at_match
    name: exclude_static
    pattern: "\\.(css|js|png)\\s"
```

### OpenTelemetry
```yaml
processors:
  filter/static:
    logs:
      log_record:
        - 'IsMatch(body, ".*\\.(css|js|png)\\s.*")'
```

---

## Common Patterns

### SSN
| | Pattern |
|---|---------|
| Datadog | `\\d{3}-\\d{2}-\\d{4}` |
| OTel | `\\d{3}-\\d{2}-\\d{4}` |

### Email
| | Pattern |
|---|---------|
| Datadog | `[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}` |
| OTel | `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}` |

### Credit Card (Visa)
| | Pattern |
|---|---------|
| Datadog | `\\b4[0-9]{12}(?:[0-9]{3})?\\b` |
| OTel | `\\b4[0-9]{12}(?:[0-9]{3})?\\b` |

### IP Address
| | Pattern |
|---|---------|
| Datadog | `(?:(?:25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)` |
| OTel | Same pattern |

### Bearer Token
| | Pattern |
|---|---------|
| Datadog | `Bearer\\s+[a-zA-Z0-9._-]+` |
| OTel | `Bearer\\s+[a-zA-Z0-9._-]+` |

---

## Pipeline Order (Recommended)

```yaml
service:
  pipelines:
    logs:
      processors:
        - memory_limiter      # 1. Prevent OOM
        - k8sattributes       # 2. Add K8s metadata
        - filter/namespace    # 3. Drop namespaces (early)
        - filter/healthcheck  # 4. Drop health checks
        - filter/severity     # 5. Drop by severity
        - transform/pii       # 6. Mask PII
        - transform/enrich    # 7. Add attributes
        - batch               # 8. Batch (always last)
```

---

## OTTL Quick Reference

### Drop if matches
```yaml
filter:
  logs:
    log_record:
      - 'IsMatch(body, "pattern")'
```

### Replace pattern
```yaml
transform:
  log_statements:
    - context: log
      statements:
        - replace_pattern(body, "find", "replace")
```

### Set attribute
```yaml
transform:
  log_statements:
    - context: resource
      statements:
        - set(attributes["key"], "value")
```

### Conditional
```yaml
transform:
  log_statements:
    - context: log
      statements:
        - set(severity_text, "ERROR") where IsMatch(body, "(?i)error")
```

---

## Severity Numbers

| Level | Number | Constant |
|-------|--------|----------|
| TRACE | 1 | `SEVERITY_NUMBER_TRACE` |
| DEBUG | 5 | `SEVERITY_NUMBER_DEBUG` |
| INFO | 9 | `SEVERITY_NUMBER_INFO` |
| WARN | 13 | `SEVERITY_NUMBER_WARN` |
| ERROR | 17 | `SEVERITY_NUMBER_ERROR` |
| FATAL | 21 | `SEVERITY_NUMBER_FATAL` |

---

## Resource Attributes (K8s)

| Attribute | Description |
|-----------|-------------|
| `k8s.namespace.name` | Namespace |
| `k8s.pod.name` | Pod name |
| `k8s.pod.uid` | Pod UID |
| `k8s.container.name` | Container name |
| `k8s.deployment.name` | Deployment |
| `k8s.node.name` | Node |
| `service.name` | Service name |

---

## Last9 Export Configuration

```yaml
exporters:
  otlp/last9:
    endpoint: "${LAST9_OTLP_ENDPOINT}"
    headers:
      Authorization: "${LAST9_AUTH_TOKEN}"
    compression: gzip
```

---

## Debugging Tips

1. **Enable debug exporter**:
```yaml
exporters:
  debug:
    verbosity: detailed
```

2. **Check collector logs**:
```bash
kubectl logs -n last9 -l app.kubernetes.io/name=last9-otel-collector -f
```

3. **Test OTTL conditions**:
Set `error_mode: ignore` to continue on errors, `propagate` to fail.

4. **Validate regex**:
OTTL uses RE2 syntax (same as Golang). Test at https://regex101.com with "Golang" flavor.

---

## 6. Multi-line Log Aggregation

### Datadog
```yaml
log_processing_rules:
  - type: multi_line
    name: java_stacktrace
    pattern: "^\\d{4}-\\d{2}-\\d{2}"
```

### OpenTelemetry
```yaml
receivers:
  filelog:
    operators:
      - type: recombine
        combine_field: body
        is_first_entry: body matches "^\\d{4}-\\d{2}-\\d{2}"
        source_identifier: attributes["log.file.path"]
        max_log_size: 1048576
```

---

## 7. JSON Parsing

### Datadog
```yaml
# Automatic - Datadog auto-detects JSON
ad.datadoghq.com/app.logs: |
  [{"source": "nodejs", "service": "api"}]
```

### OpenTelemetry
```yaml
receivers:
  filelog:
    operators:
      - type: json_parser
        parse_from: attributes.log
        parse_to: attributes
```

---

## 8. Grok/Regex Parsing

### Datadog (Cloud Pipeline)
```
# Grok pattern
%{IPORHOST:client_ip} %{NOTSPACE} %{NOTSPACE} \[%{HTTPDATE:timestamp}\] "%{WORD:method} %{NOTSPACE:path}"
```

### OpenTelemetry
```yaml
receivers:
  filelog:
    operators:
      - type: regex_parser
        regex: '^(?P<client_ip>[^ ]+) [^ ]+ [^ ]+ \[(?P<timestamp>[^\]]+)\] "(?P<method>\w+) (?P<path>[^ ]+)"'
```

---

## VRL to OTTL Mapping

| VRL | OTTL |
|-----|------|
| `del(.field)` | `delete_key(attributes, "field")` |
| `.field = "value"` | `set(attributes["field"], "value")` |
| `exists(.field)` | `attributes["field"] != nil` |
| `upcase(.field)` | `ConvertCase(attributes["field"], "upper")` |
| `downcase(.field)` | `ConvertCase(attributes["field"], "lower")` |
| `replace(s, pat, rep)` | `replace_pattern(s, "pat", "rep")` |
| `match(s, regex)` | `IsMatch(s, "regex")` |
| `contains(s, sub)` | `IsMatch(s, ".*sub.*")` |
| `to_int(v)` | `Int(v)` |
| `to_float(v)` | `Double(v)` |
| `now()` | `Now()` |
| `abort` | Use `filter` processor |
| `if .x == y { }` | `... where x == y` |
| `merge(a, b)` | `merge_maps(a, b, "upsert")` |
| `sha256(s)` | `SHA256(s)` |
| `uuid_v4()` | `UUID()` |

---

## Filelog Operators

| Operator | Purpose |
|----------|---------|
| `json_parser` | Parse JSON to attributes |
| `regex_parser` | Parse with regex named groups |
| `recombine` | Aggregate multi-line logs |
| `severity_parser` | Extract severity level |
| `time_parser` | Parse timestamp |
| `key_value_parser` | Parse key=value pairs |
| `router` | Route to different operators |
| `move` | Move field to new location |
| `add` | Add static attribute |

---

## Documentation Links

**OTTL**:
- Functions: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/pkg/ottl/ottlfuncs
- Contexts: https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/ottl/contexts/README.md

**Processors**:
- Filter: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/filterprocessor
- Transform: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/transformprocessor

**Filelog Operators**:
- Overview: https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/README.md
- Recombine: https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/recombine.md
- JSON Parser: https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/json_parser.md
- Regex Parser: https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/regex_parser.md
