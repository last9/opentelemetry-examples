#!/usr/bin/env bash
# Probe a remote MCP server without saving it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

BASE="$(ai_base)"
echo "POST ${BASE}/mcp-servers/test"
http_json -X POST "${BASE}/mcp-servers/test" \
  -H "$(auth_header)" \
  -H 'Content-Type: application/json' \
  -d "$(mcp_payload)"
