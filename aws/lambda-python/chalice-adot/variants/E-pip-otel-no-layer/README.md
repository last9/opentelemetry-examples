# Variant E — pip-only OpenTelemetry, no ADOT layer

The Chalice app installs `opentelemetry-*` packages via `requirements.txt`, then a
shared `otel_init.py` module activates the instrumentations at module load. No
Lambda layers attached — single deployment artifact.

## Why this variant

- A/B/C exposed Chalice ↔ ADOT-layer interaction quirks (sys.path, missing module
  errors, 250 MB layer ceiling). Variant E sidesteps the entire layer dance.
- Function zip stays smaller than A/B/C-with-deps (~25-35 MB vs ~140 MB), well
  under the 250 MB unzipped ceiling.
- No in-Lambda collector subprocess — direct OTLP HTTP export from SDK.
- Local development (`chalice local`, `pytest`) skips OTel init entirely; only
  the Lambda runtime activates instrumentation.

## How auto-instrumentation works here

Python OTel "auto-instrumentation" is **monkey-patching at instrument-call time**,
not magic. Each `Instrumentor().instrument()` call patches methods on already-
imported modules and hooks `sys.meta_path` so future imports get patched too.

```
Lambda cold start
  → Lambda runtime imports app.py (module load)
    → init_otel() runs once
      → AwsLambdaInstrumentor patches lambda_handler wrapper
      → BotocoreInstrumentor patches BaseClient.[op] methods
      → RequestsInstrumentor patches Session.send
      → URLLib3Instrumentor patches connectionpool.urlopen
      → LoggingInstrumentor injects trace_id into log records
  → Lambda invokes handler
    → all patched code emits spans automatically
```

Coverage parity with ADOT layer is determined by **which instrumentation packages
are installed**. Use `scripts/bootstrap-requirements.sh` to auto-detect what your
app needs (it scans installed deps and emits matching packages).

## Local skip guard

`otel_init.py` returns early unless `AWS_LAMBDA_FUNCTION_NAME` is set (or
`OTEL_FORCE_INIT=1` for explicit local testing). This means:

- `chalice local --stage dev` → no OTel, no OTLP attempt, no errors about missing endpoint
- `pytest` → no OTel
- `chalice deploy` then real invocation → Lambda runtime sets the var → init runs

## Operator: step-by-step to deploy

Run these from the **chalice-adot repo root**:

### 1. One-time: install Chalice + AWS credentials

```bash
# Install chalice if not already (uv recommended; pipx also fine)
uv tool install --python 3.12 chalice

# AWS creds — must point at the target account
export AWS_PROFILE=experiments-engineer   # or whichever role you assume
export AWS_REGION=ap-south-1
export AWS_DEFAULT_REGION=ap-south-1
aws sts get-caller-identity  # sanity check
```

### 2. Set Last9 credentials

Create `.env` in the repo root (gitignored):

```bash
cat > .env <<EOF
LAST9_OTLP_AUTH="Basic <base64-of-cluster:token>"
EOF
```

Get the auth header from Last9 → Integrations → OpenTelemetry → "Show credentials".

### 3. (Optional but recommended) Regenerate instrumentation list

If you've added new deps to `variants/E-pip-otel-no-layer/requirements.txt`
(e.g. `redis`, `psycopg2-binary`), run:

```bash
./scripts/bootstrap-requirements.sh variants/E-pip-otel-no-layer
```

This spins up an ephemeral venv, installs your app deps, runs
`opentelemetry-bootstrap -a requirements`, and (after y/N confirmation) appends
matching `opentelemetry-instrumentation-*` packages to `requirements.txt`.
Review + de-dupe before deploy.

### 4. Substitute the auth header into the config

Chalice doesn't expand env vars in `config.json`. Variant E ships a `.in` template
that the deploy script substitutes via `sed`. If running E manually outside
`scripts/deploy-all.sh`:

```bash
cd variants/E-pip-otel-no-layer
set -a; source ../../.env; set +a
sed "s#__LAST9_OTLP_AUTH__#${LAST9_OTLP_AUTH}#g" \
  .chalice/config.json.in > .chalice/config.json
```

(The generated `.chalice/config.json` is gitignored — see top-level `.gitignore`.)

### 5. Deploy

```bash
chalice deploy --stage dev
```

Or via the top-level orchestrator:

```bash
bash scripts/deploy-all.sh   # deploys A/B/C/E together
```

### 6. Invoke + verify

```bash
url=$(chalice url --stage dev)
curl -s "${url}"  # should return {"filetype_version":"1.2.0","aiohttp_version":"3.13.5"}
```

Check Last9: filter by `service.name=chalice-adot-e` — traces should
appear within ~10s of the first request.

CloudWatch logs:

```bash
aws logs tail /aws/lambda/chalice-adot-e-dev --since 2m
```

Look for log lines with `trace_id=...` (LoggingInstrumentor injection) — confirms
instrumentation is active.

### 7. Teardown when done

```bash
cd variants/E-pip-otel-no-layer
chalice delete --stage dev
```

## When to use this in real customer projects

- Customer's existing deployment hits the 250 MB layer/zip ceiling with ADOT layer attached
- Customer wants a single deployment artifact (no layer ARN management)
- Customer is OK with a small, contained code change to `app.py` (one `init_otel()` call)
- Customer's logging library is `Microsoft.Extensions.Logging`-style `logging` (so LoggingInstrumentor works); log4net-style libs in non-Python Lambdas don't apply here

## Comparison vs Variants A/B/C/D

| | A (`automatic_layer: true`) | B/C (zip-bundled) | D (explicit deps layer) | **E (pip + no ADOT)** |
|--|---|---|---|---|
| ADOT layer attached | ✅ | ✅ | ✅ | ❌ |
| Chalice managed layer | ✅ | ❌ | ✅ | ❌ |
| Function zip size | tiny | ~140 MB | tiny | ~25-35 MB |
| Total unzipped size | ~240 MB | ~240 MB | ~240 MB | **~35 MB** |
| Risk of 250 MB ceiling | high | high | high | **negligible** |
| Code change in `app.py` | none | none | none | **3 lines** (one `init_otel()` call) |
| Telemetry export path | SDK → ADOT collector → Last9 | SDK → ADOT collector → Last9 | SDK → ADOT collector → Last9 | **SDK → Last9 directly** |
| Extension.InitError risk | yes | yes | yes | **no** (no extension) |
| Cold start overhead | ~1s (extension boot + collector init) | ~1s | ~1s | ~500ms (SDK init only) |
