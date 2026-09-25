#!/usr/bin/env bash
# Shared helpers for Last9 AI knowledge + remote MCP setup scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

LAST9_HOST="${LAST9_HOST:-https://app.last9.io}"
MCP_NAME="${MCP_NAME:-payments}"
MCP_URL="${MCP_URL:-https://mcp.example.com/mcp}"
MCP_AUTH_HEADER="${MCP_AUTH_HEADER:-}"
TOPIC_ID="${TOPIC_ID:-payments-incident-playbook}"
TOPIC_NAME="${TOPIC_NAME:-Payments incident playbook}"

require_env() {
  local missing=0
  for key in "$@"; do
    if [[ -z "${!key:-}" ]]; then
      echo "Missing required env: ${key}" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    echo "Copy .env.example to .env and fill in values." >&2
    exit 1
  fi
}

ai_base() {
  require_env LAST9_ORG LAST9_ACCESS_TOKEN
  echo "${LAST9_HOST}/api/v4/organizations/${LAST9_ORG}/ai"
}

auth_header() {
  require_env LAST9_ACCESS_TOKEN
  echo "X-LAST9-API-TOKEN: Bearer ${LAST9_ACCESS_TOKEN}"
}

mcp_payload() {
  require_env MCP_NAME MCP_URL
  if [[ -n "${MCP_AUTH_HEADER}" ]]; then
    jq -n \
      --arg name "${MCP_NAME}" \
      --arg url "${MCP_URL}" \
      --arg auth "${MCP_AUTH_HEADER}" \
      '{name:$name, transport:"streamablehttp", url:$url, headers:{Authorization:$auth}}'
  else
    jq -n \
      --arg name "${MCP_NAME}" \
      --arg url "${MCP_URL}" \
      '{name:$name, transport:"streamablehttp", url:$url, headers:{}}'
  fi
}

pretty() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    cat
  fi
}

# curl wrapper that fails on non-2xx before dependent steps continue.
# Usage: http_json [curl args...]
http_json() {
  local body code rc=0
  body="$(mktemp)"
  code="$(curl -sS -o "${body}" -w '%{http_code}' "$@")" || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    rm -f "${body}"
    return "${rc}"
  fi
  if [[ ! "${code}" =~ ^2[0-9][0-9]$ ]]; then
    echo "HTTP ${code}:" >&2
    cat "${body}" >&2
    echo >&2
    rm -f "${body}"
    return 1
  fi
  pretty <"${body}"
  rm -f "${body}"
}

etag_from_headers() {
  # Reads curl -D headers from stdin; prints quoted ETag value.
  # Portable case-insensitive match (works with mawk; avoids gawk IGNORECASE).
  awk '
    tolower($0) ~ /^etag:/ {
      sub(/\r$/, "")
      sub(/^[^:]+:[[:space:]]*/, "")
      print
      exit
    }
  '
}
