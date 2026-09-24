#!/usr/bin/env bash
# Register a remote MCP server for Last9 AI.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

BASE="$(ai_base)"
echo "POST ${BASE}/mcp-servers"
curl -sS -X POST "${BASE}/mcp-servers" \
  -H "$(auth_header)" \
  -H 'Content-Type: application/json' \
  -d "$(mcp_payload)" | pretty

echo
echo "GET ${BASE}/mcp-servers/${MCP_NAME}"
curl -sS "${BASE}/mcp-servers/${MCP_NAME}" \
  -H "$(auth_header)" | pretty
