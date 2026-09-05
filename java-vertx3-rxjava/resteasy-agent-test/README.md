# RESTEasy Agent Test App

Tests three FDE-196 fixes in `vertx3-otel-agent`:

| Bug | Endpoint | What to verify on span |
|-----|----------|------------------------|
| Bug 1 — body capture | `POST /api/v1/contests/{id}/submit` | `http.request.body = {"teamId":"t1","wsId":123}` |
| Bug 2 — async exception | `POST /api/v1/contests/{id}/fail` | exception event + `status = ERROR` |
| Bug 3 — url.query | `GET /api/v1/contests/{id}?wsId=123` | `url.query = wsId=123` |

## Prerequisites

The `pom.xml` currently references `2.3.5-beta.9` (released, no FDE-196 fixes).

To test FDE-196 fixes, build the agent from the `errors` branch and update `agent.version`:

```bash
cd ~/Projects/vertx-rxjava3-otel-autoconfigure
git checkout errors
mvn install -DskipTests
# Then in pom.xml: <agent.version>2.3.5-SNAPSHOT</agent.version>
```

Without that change the app still runs and traces, but:
- Bug 2 (`/fail`): no exception event on the span
- Bug 1 (`/submit`): no `http.request.body` attribute
- Bug 3 (`/contests/42?wsId=...`): no `url.query` attribute

## Run locally (no Docker)

```bash
cp .env.example .env
# edit .env with your OTLP endpoint

mvn package -DskipTests
source .env
java -javaagent:target/vertx3-otel-agent.jar -jar target/resteasy-agent-test-1.0.0.jar
```

## Run with Docker Compose

```bash
cp .env.example .env
# edit .env

mvn package -DskipTests
docker-compose up --build
```

## Test calls

```bash
# Bug 3: url.query
curl "http://localhost:8080/api/v1/contests/42?wsId=123&tournamentId=456"
# Span should have: url.query=wsId=123&tournamentId=456

# Bug 1: body capture (needs VERTX_OTEL_BODY_CAPTURE_ENABLED=true)
curl -X POST http://localhost:8080/api/v1/contests/42/submit \
  -H "Content-Type: application/json" \
  -d '{"teamId":"t1","wsId":123}'
# Span should have: http.request.body={"teamId":"t1","wsId":123}

# Bug 2: async exception — RESTEasy calls writeException, not invoke throw
curl -X POST http://localhost:8080/api/v1/contests/42/fail \
  -H "Content-Type: application/json" \
  -d '{"teamId":"t1"}'
# Span should have: status=ERROR, exception event "simulated team submission failure for contest 42"
# Also: http.request.body={"teamId":"t1"} (with body capture + errorOnly=true, status is unknown at startSpan so endSpan uses thrown!=null check)

# Baseline: sync exception (always worked, for comparison)
curl -X POST http://localhost:8080/api/v1/contests/42/fail-sync \
  -H "Content-Type: application/json" \
  -d '{"teamId":"t1"}'

# Error-only body capture (VERTX_OTEL_BODY_CAPTURE_ERROR_ONLY=true alone)
# Set VERTX_OTEL_BODY_CAPTURE_ERROR_ONLY=true, remove VERTX_OTEL_BODY_CAPTURE_ENABLED
# Then hit /fail — body should appear; hit /submit (200) — body should NOT appear
```

## Env vars reference

| Var | Effect |
|-----|--------|
| `VERTX_OTEL_BODY_CAPTURE_ENABLED=true` | Capture body on all requests |
| `VERTX_OTEL_BODY_CAPTURE_ERROR_ONLY=true` | Capture body only on 4xx/5xx (or when exception thrown). No `ENABLED` needed. |
| `VERTX_OTEL_BODY_CAPTURE_MAX_BYTES=8192` | Truncate body at N bytes (default 8192) |
