#!/usr/bin/env bash
# Delete the example topic and MCP server (requires delete scope + If-Match).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

BASE="$(ai_base)"
HDRS="$(mktemp)"
BODY="$(mktemp)"
trap 'rm -f "${HDRS}" "${BODY}"' EXIT

delete_with_etag() {
  local path="$1"
  curl -sS -D "${HDRS}" -o "${BODY}" "${BASE}${path}" -H "$(auth_header)"
  local etag
  etag="$(etag_from_headers <"${HDRS}")"
  if [[ -z "${etag}" ]]; then
    echo "No ETag for ${path}; response:" >&2
    cat "${BODY}" >&2
    exit 1
  fi
  echo "DELETE ${BASE}${path} If-Match: ${etag}"
  curl -sS -X DELETE "${BASE}${path}" \
    -H "$(auth_header)" \
    -H "If-Match: ${etag}" | pretty
}

echo "Deleting topic ${TOPIC_ID} (if present)..."
delete_with_etag "/knowledge/topics/${TOPIC_ID}" || true

echo
echo "Deleting MCP server ${MCP_NAME} (if present)..."
delete_with_etag "/mcp-servers/${MCP_NAME}" || true
