#!/usr/bin/env bash
# Show config activation status and current MCP / knowledge resources.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

BASE="$(ai_base)"

echo "== config/status =="
curl -sS "${BASE}/config/status" -H "$(auth_header)" | pretty

echo
echo "== mcp-servers =="
curl -sS "${BASE}/mcp-servers" -H "$(auth_header)" | pretty

echo
echo "== knowledge/topics =="
curl -sS "${BASE}/knowledge/topics" -H "$(auth_header)" | pretty
