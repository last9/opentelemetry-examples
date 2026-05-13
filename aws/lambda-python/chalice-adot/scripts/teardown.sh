#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANTS=(
  "A-automatic-layer-true"
  "B-automatic-layer-false"
  "C-automatic-layer-unset"
  "D-explicit-layers"
)

for variant in "${VARIANTS[@]}"; do
  echo "=== chalice delete: ${variant} ==="
  VDIR="${ROOT}/variants/${variant}"
  cd "${VDIR}"

  if [[ "${variant}" == "D-explicit-layers" && ! -f "${VDIR}/.chalice/config.json" ]]; then
    if [[ -n "${DEPS_LAYER_ARN:-}" ]]; then
      sed "s#__DEPS_LAYER_ARN__#${DEPS_LAYER_ARN}#g" "${VDIR}/.chalice/config.json.in" > "${VDIR}/.chalice/config.json"
    else
      echo "Skipping D: create .chalice/config.json (deploy once) or set DEPS_LAYER_ARN for teardown."
      continue
    fi
  fi

  chalice delete --stage dev || true
done
