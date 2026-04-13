#!/bin/bash
# End-to-end test for Spring Boot 3.2 (Jakarta servlet) with last9-otel-body-capture extension.
# Verifies that http.request.body and http.response.body appear as span attributes.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_URL="http://localhost:8086"
PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
info()  { printf '\033[34m%s\033[0m\n' "$*"; }

check() {
    local desc="$1" expected="$2"
    if docker logs body-capture-jakarta-collector 2>&1 | grep -q "$expected"; then
        green "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        red   "  FAIL: $desc (expected to find '$expected' in collector logs)"
        FAIL=$((FAIL + 1))
    fi
}

# ── 1. Start infrastructure ───────────────────────────────────────────────────
info "Starting OTel collector..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

# ── 2. Start app in background ────────────────────────────────────────────────
info "Starting sample app (Spring Boot 3.2 / Jakarta)..."
"$SCRIPT_DIR/start_app.sh" > /tmp/bodycapture-jakarta-app.log 2>&1 &
APP_PID=$!

info "Waiting for app to be ready..."
for i in $(seq 1 60); do
    if curl -sf "$APP_URL/api/health" > /dev/null 2>&1; then
        green "App is up."
        break
    fi
    if [ $i -eq 60 ]; then
        red "App did not start in time. Logs:"
        tail -30 /tmp/bodycapture-jakarta-app.log
        kill $APP_PID 2>/dev/null || true
        docker compose -f "$SCRIPT_DIR/docker-compose.yml" down
        exit 1
    fi
    sleep 2
done

# ── 3. Send test requests ─────────────────────────────────────────────────────
info ""
info "Sending test requests..."

curl -sf -X POST "$APP_URL/api/echo" \
    -H "Content-Type: application/json" \
    -d '{"message":"hello world","user":"alice"}' > /dev/null

curl -sf -X POST "$APP_URL/api/users" \
    -H "Content-Type: application/json" \
    -d '{"name":"bob","email":"bob@example.com"}' > /dev/null

curl -sf "$APP_URL/api/users/1" > /dev/null
curl -sf "$APP_URL/api/users/999" > /dev/null || true

info "Waiting for spans to flush to collector..."
sleep 5

# ── 4. Verify span attributes ─────────────────────────────────────────────────
info ""
info "Checking collector logs for body attributes..."

check "http.request.body present on POST /api/echo"  "http.request.body"
check "http.response.body present on POST /api/echo" "http.response.body"
check "POST /api/users request body captured"        "bob@example.com"
check "hello world captured in request body"         "hello world"

# ── 5. Teardown ───────────────────────────────────────────────────────────────
info ""
info "Stopping app and collector..."
kill $APP_PID 2>/dev/null || true
wait $APP_PID 2>/dev/null || true
docker compose -f "$SCRIPT_DIR/docker-compose.yml" down

# ── 6. Results ────────────────────────────────────────────────────────────────
info ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && green "All tests passed." || { red "Some tests failed."; exit 1; }
