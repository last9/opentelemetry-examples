#!/usr/bin/env bash
# Show config activation status and current MCP / knowledge resources.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

BASE="$(ai_base)"

echo "== config/status =="
http_json "${BASE}/config/status" -H "$(auth_header)"

echo
echo "== mcp-servers =="
http_json "${BASE}/mcp-servers" -H "$(auth_header)"

echo
echo "== knowledge/topics =="
http_json "${BASE}/knowledge/topics" -H "$(auth_header)"
