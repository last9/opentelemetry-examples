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
  local code
  code="$(curl -sS -o "${BODY}" -D "${HDRS}" -w '%{http_code}' "${BASE}${path}" -H "$(auth_header)")"
  if [[ "${code}" == "404" ]]; then
    echo "Skip ${path} (not found)"
    return 0
  fi
  if [[ "${code}" != "200" ]]; then
    echo "GET ${path} failed (${code}):" >&2
    cat "${BODY}" >&2
    return 1
  fi
  local etag
  etag="$(etag_from_headers <"${HDRS}")"
  if [[ -z "${etag}" ]]; then
    echo "No ETag for ${path}; response:" >&2
    cat "${BODY}" >&2
    return 1
  fi
  echo "DELETE ${BASE}${path} If-Match: ${etag}"
  code="$(curl -sS -o "${BODY}" -w '%{http_code}' -X DELETE "${BASE}${path}" \
    -H "$(auth_header)" \
    -H "If-Match: ${etag}")"
  if [[ ! "${code}" =~ ^2[0-9][0-9]$ ]]; then
    echo "DELETE ${path} failed (${code}):" >&2
    cat "${BODY}" >&2
    return 1
  fi
  if [[ -s "${BODY}" ]]; then
    pretty <"${BODY}"
  fi
}

echo "Deleting topic ${TOPIC_ID} (if present)..."
delete_with_etag "/knowledge/topics/${TOPIC_ID}"

echo
echo "Deleting MCP server ${MCP_NAME} (if present)..."
delete_with_etag "/mcp-servers/${MCP_NAME}"
