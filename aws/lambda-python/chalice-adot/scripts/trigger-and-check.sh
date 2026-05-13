#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-ap-south-1}"

VARIANT_DIRS=(
  "A-automatic-layer-true"
  "B-automatic-layer-false"
  "C-automatic-layer-unset"
  "D-explicit-layers"
)

FUNCS=(
  "chalice-adot-a"
  "chalice-adot-b"
  "chalice-adot-c"
  "chalice-adot-d"
)

for i in "${!VARIANT_DIRS[@]}"; do
  folder="${VARIANT_DIRS[$i]}"
  logical="${FUNCS[$i]}"
  fn_name="${logical}-dev"

  echo "=== ${logical} (variants/${folder}) ==="
  if ! url="$(cd "${ROOT}/variants/${folder}" && chalice url --stage dev)"; then
    echo "chalice url failed (deploy this variant first)."
    echo ""
    continue
  fi
  echo "URL: ${url}"

  for _ in 1 2 3; do
    code="$(curl -sS -o /tmp/chalice-adot-resp.json -w "%{http_code}" "${url}" || true)"
    echo "HTTP ${code}"
    cat /tmp/chalice-adot-resp.json || true
    echo ""
  done

  log_group="/aws/lambda/${fn_name}"
  echo "--- recent ERROR lines (${log_group}) ---"
  aws logs tail "${log_group}" --since 5m --filter-pattern "ERROR" --region "${REGION}" 2>/dev/null | head -20 || echo "(no logs or log group missing yet)"
  echo ""
done
