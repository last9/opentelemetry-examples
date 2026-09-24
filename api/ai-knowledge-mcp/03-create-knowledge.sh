#!/usr/bin/env bash
# Create an incident_triage knowledge topic, bind MCP tools, upload a runbook.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

BASE="$(ai_base)"
RUNBOOK="${SCRIPT_DIR}/fixtures/sev1-runbook.md"

TOPIC_BODY="$(jq -n \
  --arg id "${TOPIC_ID}" \
  --arg name "${TOPIC_NAME}" \
  --arg server "${MCP_NAME}" \
  '{
    id: $id,
    name: $name,
    description: "How to triage payments and ledger incidents",
    overview: ("For SEV1/2 payments incidents: call get_incident on the " + $server + " MCP, then Last9 traces and logs for the same service and window, then add_comment. Prefer " + $id + "__* tools over raw mcp__" + $server + "__* names."),
    use: ["incident_triage"],
    mcp: [
      {server: $server, tools: ["get_incident", "add_comment"], approval: "auto"},
      {server: $server, tools: ["close_incident"], approval: "approve"}
    ]
  }')"

echo "POST ${BASE}/knowledge/topics"
curl -sS -X POST "${BASE}/knowledge/topics" \
  -H "$(auth_header)" \
  -H 'Content-Type: application/json' \
  -d "${TOPIC_BODY}" | pretty

echo
echo "POST ${BASE}/knowledge/topics/${TOPIC_ID}/documents (multipart)"
curl -sS -X POST "${BASE}/knowledge/topics/${TOPIC_ID}/documents" \
  -H "$(auth_header)" \
  -F 'id=sev1-runbook' \
  -F 'title=SEV1 payments runbook' \
  -F "file=@${RUNBOOK};type=text/markdown" | pretty
