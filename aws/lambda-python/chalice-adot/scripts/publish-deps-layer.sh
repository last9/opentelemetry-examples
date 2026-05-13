#!/usr/bin/env bash
# Build a Lambda layer zip from this variant's requirements.txt (Python 3.x layout).
# Usage (from repo root):
#   cd aws/lambda-python/chalice-adot/variants/D-explicit-layers
#   ../../scripts/publish-deps-layer.sh
#
# Then set DEPS_LAYER_ARN in .env to the published layer version ARN.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VARIANT_DIR="${ROOT}/variants/D-explicit-layers"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

python3 -m pip install -r "${VARIANT_DIR}/requirements.txt" -t "${WORKDIR}/python"
(
  cd "${WORKDIR}"
  zip -qr layer.zip python
)

echo "Layer zip: ${WORKDIR}/layer.zip"
echo "Publish (replace account/region/name):"
echo "  aws lambda publish-layer-version --layer-name chalice-adot-deps \\"
echo "    --zip-file fileb://${WORKDIR}/layer.zip --compatible-runtimes python3.9 python3.10 python3.11 python3.12 \\"
echo "    --region ap-south-1"
