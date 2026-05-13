#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source .env first so its values are available to the required-var checks below.
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ROOT}/.env"
  set +a
fi

: "${LAST9_OTLP_AUTH:?LAST9_OTLP_AUTH not set (put it in .env)}"
: "${LAMBDA_EXEC_ROLE_ARN:?LAMBDA_EXEC_ROLE_ARN not set (existing IAM role with AWSLambdaBasicExecutionRole; put it in .env)}"
export AWS_REGION="${AWS_REGION:-ap-south-1}"

VARIANTS=(
  "A-automatic-layer-true"
  "B-automatic-layer-false"
  "C-automatic-layer-unset"
  "D-explicit-layers"
  "E-pip-otel-no-layer"
)

for variant in "${VARIANTS[@]}"; do
  echo "=== Deploying ${variant} ==="
  VDIR="${ROOT}/variants/${variant}"
  cd "${VDIR}"

  if [[ "${variant}" == "D-explicit-layers" && -z "${DEPS_LAYER_ARN:-}" ]]; then
    echo "Skipping D: set DEPS_LAYER_ARN in the environment (or .env) to deploy variant D."
    continue
  fi

  # Variants A-D use the ADOT layer + in-Lambda collector. Variant E has no
  # collector subprocess (direct SDK export), so no collector-config.yaml.
  if [[ -f "${VDIR}/chalicelib/collector-config.yaml.tmpl" ]]; then
    envsubst < "${VDIR}/chalicelib/collector-config.yaml.tmpl" > "${VDIR}/chalicelib/collector-config.yaml"
  fi

  # All variants ship .chalice/config.json.in. Substitute the placeholders that
  # apply to this variant. Chalice does not expand env vars inside config.json
  # itself, so we materialize the real config at deploy time.
  CONFIG_IN="${VDIR}/.chalice/config.json.in"
  CONFIG_OUT="${VDIR}/.chalice/config.json"

  sed \
    -e "s#__LAMBDA_EXEC_ROLE_ARN__#${LAMBDA_EXEC_ROLE_ARN}#g" \
    -e "s#__LAST9_OTLP_AUTH__#${LAST9_OTLP_AUTH}#g" \
    -e "s#__DEPS_LAYER_ARN__#${DEPS_LAYER_ARN:-arn:aws:lambda:placeholder:0:layer:none:0}#g" \
    "${CONFIG_IN}" > "${CONFIG_OUT}"

  chalice deploy --stage dev
done

echo "Done. Run scripts/verify-layers.sh and scripts/trigger-and-check.sh."
