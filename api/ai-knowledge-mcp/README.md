# Last9 AI — remote MCP + knowledge setup

Shell example that registers a remote MCP server for Last9 AI, creates an `incident_triage` knowledge topic with tool bindings, and uploads an app runbook.

Product docs (merge [last9.io#805](https://github.com/last9/last9.io/pull/805) first if these 404):

- [Remote MCP servers](https://last9.io/docs/ai/remote-mcp-servers/)
- [Knowledge](https://last9.io/docs/ai/knowledge/)
- [Getting started with API](https://last9.io/docs/getting-started-with-api/)

## Prerequisites

- `curl` and `jq`
- Last9 AI enabled for the organization
- Admin user + API refresh token with **write** (and **delete** for teardown)
- A short-lived access token from `POST /api/v4/oauth/access_token`
- A reachable HTTPS remote MCP endpoint (optional for dry-run of scripts; required for a green diagnostic)

## Quick Start

```bash
cd api/ai-knowledge-mcp
cp .env.example .env
# Edit .env: LAST9_ORG, LAST9_ACCESS_TOKEN, MCP_URL, MCP_AUTH_HEADER

chmod +x ./*.sh
./01-test-mcp.sh          # probe only — does not save
./02-register-mcp.sh      # save MCP server
./03-create-knowledge.sh  # topic + runbook document
./04-status.sh            # config/status, servers, topics
```

Then open [AI Assistant](https://app.last9.io/ai-assistant), send one chat turn to activate (`pending` → `active`), and ask the assistant to follow the payments playbook.

Teardown (needs **delete** scope):

```bash
./05-teardown.sh
```

## Configuration

| Variable | Required | Description |
| --- | --- | --- |
| `LAST9_ORG` | yes | Organization slug |
| `LAST9_ACCESS_TOKEN` | yes | Bearer access token (`X-LAST9-API-TOKEN`) |
| `LAST9_HOST` | no | Default `https://app.last9.io` |
| `MCP_NAME` | no | Default `payments` (cannot be `test`; lowercase) |
| `MCP_URL` | yes for MCP steps | HTTPS MCP endpoint |
| `MCP_AUTH_HEADER` | no | Value for `Authorization` header stored on the server |
| `TOPIC_ID` | no | Default `payments-incident-playbook` (kebab-case) |

## Verification

1. `./01-test-mcp.sh` succeeds (connection + tool discovery).
2. `./04-status.sh` lists your MCP server and topic.
3. After one AI Assistant turn, `config/status` is `active`.
4. Investigation calls topic tools like `payments-incident-playbook__get_incident` (`auto`) and requires approval for `…__close_incident`.

## Notes

- Creating an MCP server alone does not make the model prefer those tools — bind them on the knowledge topic (`use: ["incident_triage"]`) and describe the procedure in `overview` / documents.
- Raw `mcp__{server}__{tool}` calls for API-managed servers still default to **approve**; prefer `{topic_id}__{tool}` for configured auto approval.
- Do not leave an unreachable MCP server saved — it can block new chat turns until fixed or deleted.
