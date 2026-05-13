#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-ap-south-1}"

FUNCS=(
  "chalice-adot-a-dev"
  "chalice-adot-b-dev"
  "chalice-adot-c-dev"
  "chalice-adot-d-dev"
)

for fn_name in "${FUNCS[@]}"; do
  echo "=== ${fn_name} ==="
  if ! aws lambda get-function-configuration \
    --function-name "${fn_name}" \
    --region "${REGION}" \
    --query '{Layers:Layers[*].Arn,CodeSize:CodeSize,MemorySize:MemorySize}' \
    --output table 2>/dev/null; then
    echo "(function not found — deploy first)"
    echo ""
    continue
  fi

  s3_loc="$(aws lambda get-function --function-name "${fn_name}" --region "${REGION}" --query 'Code.Location' --output text)"
  zip_path="/tmp/${fn_name}.zip"
  curl -sL "${s3_loc}" -o "${zip_path}"
  echo "--- zip contents (filetype / aiohttp paths, first matches) ---"
  unzip -l "${zip_path}" 2>/dev/null | grep -E 'filetype|aiohttp' | head -10 || echo "(no matches in deployment zip — deps may be in layer(s) only)"
  echo ""
done
