# Chalice + ADOT — measured results

Fill this table after running `scripts/deploy-all.sh`, `scripts/verify-layers.sh`, and `scripts/trigger-and-check.sh` in your AWS account. Do **not** commit production credentials; use a dev Last9 workspace or dummy OTLP headers if you only need import/layer evidence.

## Tooling versions

| Field | Value (fill in) |
|-------|-----------------|
| `chalice --version` (run 1 — latest) | _TBD_ |
| `chalice --version` (run 2 — customer pin) | _TBD_ |
| Customer Chalice pin (if any) | _e.g. from customer `requirements.txt`_ |
| AWS region | _default `ap-southeast-1`_ |
| ADOT layer ARN used | _as in config_ |

## Acceptance criteria (per variant)

For each row record:

1. Layer count on the **API handler** Lambda (`<app_name>-dev`).
2. Full layer ARNs (identify ADOT vs Chalice managed vs explicit deps).
3. Deployment package size (`CodeSize` from `get-function-configuration`).
4. Whether `filetype` / `aiohttp` appear in the **downloaded deployment zip** (`unzip -l` grep) and/or are expected only under `/opt/...` in a layer.
5. HTTP `GET /` — `200` with JSON versions vs `5xx` / `ModuleNotFoundError` in logs.
6. CloudWatch — any import / `Runtime.ImportModuleError` lines.

## Results table (measured 2026-05-13 — ap-south-1 / experiments account)

| Variant | `automatic_layer` | Layer count | Layer summary | CodeSize (bytes) | filetype / aiohttp in function zip? | HTTP / import outcome | Log notes |
|---------|-------------------|------------|---------------|-------------------|--------------------------------------|------------------------|-----------|
| A | `true` | 2 | ADOT + Chalice managed-deps layer | 20,330 | ❌ no — only in managed layer at `/opt/python/lib/python3.12/site-packages/` | ❌ **HTTP 502 — `Unable to import module 'otel_wrapper': No module named 'filetype'`** | ADOT wrapper exec sets `PYTHONPATH=/opt/python:…` and execs new `python3`; Python's site discovery does not auto-add `/opt/python/lib/python3.12/site-packages/`, so managed-layer deps are invisible |
| B | `false` | 1 | ADOT only | 22,348,286 | ✅ yes — `aiohttp/`, `filetype/` at zip root | ✅ **HTTP 200 — `{"filetype_version":"1.2.0","aiohttp_version":"3.13.5"}`** | Deps bundled flat in zip → extract to `/var/task/<pkg>/` → on sys.path |
| C | *(unset)* | 1 | ADOT only | 22,348,285 | ✅ same as B | ✅ HTTP 200, same payload | Chalice 1.33 default behaves identically to `automatic_layer: false` |
| D | `true` + explicit deps ARN | _not run_ | _skipped_ | _n/a_ | _n/a_ | _n/a_ | Deferred — requires `scripts/publish-deps-layer.sh` to publish a deps-only layer first |
| **E** | **n/a — no ADOT layer at all** | **0** | _none_ | **24,210,424** (24 MB) | ✅ in function zip | ✅ **HTTP 200 — `/` returns versions, `/outbound` returns httpbin status 200** for both `requests` + `aiohttp` | Direct SDK → Last9 OTLP/HTTP. AwsLambdaInstrumentor dropped (incompatible with Chalice — wraps `app.app` which is a class, not a function). Botocore + Requests + URLLib3 + Logging + AioHttpClient instrumentation active. 24 MB zip leaves ~210 MB headroom under 250 MB ceiling |

### Why A fails — sys.path forensics

`/opt/otel-instrument` (ADOT wrapper script) sets:
```bash
export LAMBDA_LAYER_PKGS_DIR="/opt/python"
export PYTHONPATH="$LAMBDA_LAYER_PKGS_DIR:$PYTHONPATH"
export PYTHONPATH="$LAMBDA_RUNTIME_DIR:$PYTHONPATH"
exec python3 $LAMBDA_LAYER_PKGS_DIR/bin/opentelemetry-instrument "$@"
```

That `exec python3` spawns a **new Python process**. Its `sys.path` is derived from:
1. `PYTHONPATH` (env) — contains `/opt/python` but NOT `/opt/python/lib/python3.12/site-packages/`
2. Python's site.py — adds `lib/pythonX.Y/site-packages` only under `sys.prefix`, not arbitrary PYTHONPATH entries

ADOT bundles its own deps flat at `/opt/python/<pkg>/` so they resolve. Chalice's managed-deps layer puts deps at `/opt/python/lib/python3.12/site-packages/<pkg>/` — Lambda's default Python runtime would auto-add that path, but the ADOT wrapper's `exec python3` short-circuits that auto-add.

### Customer prescription

Set `"automatic_layer": false` in `.chalice/config.json` (or remove the key — `false` is the default in Chalice 1.33). Deps bundle directly in function zip at `/var/task/<pkg>/`, which is always on `sys.path`. Trade-off: function zip grows; watch the 250 MB unzipped ceiling.

### Expected hypothesis (edit after measurement)

| Variant | Layers attached (expected) | Deps location (expected) | Runtime imports (expected) |
|---------|---------------------------|--------------------------|----------------------------|
| A | ADOT + Chalice managed | `/opt/python/lib/.../site-packages` on managed layer | Works if managed layer is attached |
| B | ADOT only | Bundled under `/var/task/` | Depends on Chalice bundling |
| C | TBD | TBD | Establishes Chalice default |
| D | ADOT + explicit + possibly Chalice managed | Split across layers / zip | Confirms interaction and **layer count** risk |

## Commands reference

```bash
export AWS_REGION=ap-southeast-1
export LAST9_OTLP_AUTH='...'   # or from .env
./scripts/deploy-all.sh
./scripts/verify-layers.sh
./scripts/trigger-and-check.sh
```

## PR linkage

When opening or updating [PR #144](https://github.com/last9/opentelemetry-examples/pull/144) (or equivalent), add a short note pointing to this repro and paste the filled table (or link to this file after merge).
