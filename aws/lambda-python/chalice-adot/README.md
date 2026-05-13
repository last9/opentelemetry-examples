# Chalice + ADOT: automatic_layer behavior reference

Minimal Chalice apps that import `filetype` and `aiohttp` at cold start, combined with the AWS Distro for OpenTelemetry (ADOT) Lambda layer. Use this to see whether **`automatic_layer`** puts dependencies in Chalice’s managed Lambda layer (vs the function deployment package), and how that interacts with ADOT and optional explicit dependency layers.

In this repository the path is **`aws/lambda-python/chalice-adot/`**. Upstream [`opentelemetry-examples`](https://github.com/last9/opentelemetry-examples) may use a different folder name (for example `aws-lambda/python/chalice-adot/`); keep the layout consistent when opening a PR.

## Variants

| Directory | `automatic_layer` | Notes |
|-----------|-------------------|--------|
| `variants/A-automatic-layer-true` | `true` | ADOT layer + Chalice managed deps layer (expected: 2 layers). |
| `variants/B-automatic-layer-false` | `false` | ADOT only; deps should bundle into the deployment zip. |
| `variants/C-automatic-layer-unset` | *(key omitted)* | Establishes default for your installed Chalice version. |
| `variants/D-explicit-layers` | `true` | ADOT + **explicit** deps layer ARN + Chalice managed layer — tests layer count / ordering. Uses `.chalice/config.json.in` → generated `config.json`. |

Each app is deployed as a separate Chalice project (`chalice-adot-a` … `chalice-adot-d`) so they do not overwrite each other.

## Prerequisites

- AWS account and credentials (`aws configure` or env vars)
- Region default **`ap-southeast-1`** (override with `AWS_REGION`)
- Python 3.9+ and `pip install chalice` (and variant `requirements.txt` per folder)
- `curl`, `unzip`, `envsubst` (often in the `gettext` package), AWS CLI v2

## Quick start

1. Copy `.env.example` to `.env` and set **`LAST9_OTLP_AUTH`** to a non-production OTLP credential (or a dummy value if you only care about import/layer behavior and not export).

2. **Variant D only:** publish a dependencies-only layer and set **`DEPS_LAYER_ARN`** in `.env`. You can use `scripts/publish-deps-layer.sh` to build `layer.zip`, then `aws lambda publish-layer-version` (see script output).

3. From this directory:

   ```bash
   export AWS_REGION=ap-southeast-1
   source .env
   ./scripts/deploy-all.sh
   ```

   Variant **D** is skipped until **`DEPS_LAYER_ARN`** is set (see `.env.example`).

4. Inspect layers and zip contents, then hit each API:

   ```bash
   ./scripts/verify-layers.sh
   ./scripts/trigger-and-check.sh
   ```

5. Record outcomes in **`RESULTS.md`** (layer ARNs, zip grep, HTTP status, log errors). Include `chalice --version` output.

6. Teardown:

   ```bash
   source .env   # DEPS_LAYER_ARN needed for D if config.json was removed
   ./scripts/teardown.sh
   ```

## Configuration details

- **ADOT layer** in each variant points at `aws-otel-python-amd64-ver-1-32-0:2` in `ap-southeast-1`. Update the ARN in `.chalice/config.json` (or `config.json.in` for D) for your region and version.
- **Collector config** is built from `.chalice/collector-config.yaml.tmpl` via `envsubst` so secrets are not committed. The generated `.chalice/collector-config.yaml` is gitignored.
- **`OPENTELEMETRY_COLLECTOR_CONFIG_FILE`** is set to `/var/task/.chalice/collector-config.yaml` (Chalice packages `.chalice/` into the deployment artifact).
- Lambdas are tagged with **`Project=chalice-adot`** and **`chalice-adot-variant`** for teardown and cost attribution.

## Chalice version matrix

Repeat deploy + verify with:

1. Latest Chalice from PyPI (`pip install -U chalice`).
2. The customer’s pinned version (add to `requirements-chalice-pins.txt` and install in a clean venv).

Document both runs in `RESULTS.md` — defaults and layer behavior can differ by Chalice version.

## Customer takeaway

- If behavior matches **B** (deps in zip, ADOT layer only) but imports fail, try **`automatic_layer: true`** (variant **A**) so third-party wheels land on the managed layer path.
- If behavior already matches **A** yet imports fail, look beyond Chalice packaging (layer limit, layer order, runtime path, etc.).

## Related examples

- Simpler ADOT + Chalice sample: `aws/lambda-python/chalice/`
