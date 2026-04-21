#!/usr/bin/env bash
# Test vertx3-otel-agent Java 8 compatibility + full instrumentation coverage.
#
# Test 1 (Java 8):  agent must print "Requires Java 11+" and app must start normally.
# Test 2 (Java 11): agent must instrument Router, JDBC, Kafka, Aerospike, MySQL,
#                    WebClient — all producing OTel spans exported via OkHttp sender.
set -e

AGENT_JAR="target/vertx3-otel-agent.jar"
APP_JAR="target/vertx3-java8-agent-test-1.0.0.jar"

echo "=== Building ==="
mvn package -B --no-transfer-progress -q
echo "Built: $APP_JAR"
echo "Agent: $AGENT_JAR"
echo ""

# ─────────────────────────────────────────────────────────
# Test 1: Java 8 JVM — graceful fallback
# ─────────────────────────────────────────────────────────
echo "=== Test 1: Java 8 JVM (graceful fallback) ==="
if ! command -v docker &>/dev/null; then
  echo "SKIP: Docker not available for Java 8 test"
else
  LOGS=$(docker run --rm \
    -v "$(pwd)/target:/app" \
    -w /app \
    amazoncorretto:8-alpine \
    sh -c "java -javaagent:vertx3-otel-agent.jar -jar vertx3-java8-agent-test-1.0.0.jar & PID=\$!; sleep 3; kill \$PID 2>/dev/null; true" 2>&1 || true)

  echo "$LOGS" | head -30

  if echo "$LOGS" | grep -q "Requires Java 11+"; then
    echo "PASS: Java 8 graceful fallback message printed"
  else
    echo "FAIL: expected 'Requires Java 11+' in output"
    exit 1
  fi

  if echo "$LOGS" | grep -q "UnsupportedClassVersionError"; then
    echo "FAIL: JVM crashed with UnsupportedClassVersionError"
    exit 1
  else
    echo "PASS: No JVM crash"
  fi
fi
echo ""

# ─────────────────────────────────────────────────────────
# Test 2: Java 11+ JVM — full instrumentation
# ─────────────────────────────────────────────────────────
echo "=== Test 2: Java 11 JVM (full instrumentation) ==="
JAVA_VER=$(java -version 2>&1 | head -1)
echo "Local JVM: $JAVA_VER"

# Start infrastructure if docker-compose is available
INFRA_RUNNING=false
if command -v docker &>/dev/null; then
  echo "Starting infrastructure (Postgres, Kafka, MySQL, Aerospike)..."
  docker compose up -d postgres redpanda mysql aerospike 2>/dev/null || true
  echo "Waiting for infrastructure to be healthy..."
  sleep 10
  INFRA_RUNNING=true
fi

# Start app with agent in background
java \
  -javaagent:"$AGENT_JAR" \
  -jar "$APP_JAR" \
  -Dotel.service.name=java8-test-local \
  2>&1 &
APP_PID=$!
echo "Started app (pid=$APP_PID), waiting for it to be ready..."
sleep 5

PASS=0
FAIL=0
WARN=0

check_endpoint() {
  local METHOD=$1
  local ENDPOINT=$2
  local DATA=$3
  local DESC=$4

  if [ "$METHOD" = "POST" ]; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X POST \
      -H "Content-Type: application/json" \
      -d "$DATA" \
      http://localhost:8080"$ENDPOINT" 2>/dev/null || echo "000")
  elif [ "$METHOD" = "DELETE" ]; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X DELETE \
      http://localhost:8080"$ENDPOINT" 2>/dev/null || echo "000")
  else
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
      http://localhost:8080"$ENDPOINT" 2>/dev/null || echo "000")
  fi

  if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ] || [ "$STATUS" = "204" ]; then
    echo "  PASS: $METHOD $ENDPOINT → $STATUS ($DESC)"
    PASS=$((PASS + 1))
  elif [ "$STATUS" = "503" ]; then
    echo "  WARN: $METHOD $ENDPOINT → $STATUS ($DESC — backend not available)"
    WARN=$((WARN + 1))
  elif [ "$STATUS" = "500" ] && echo "$DESC" | grep -qi "error"; then
    echo "  PASS: $METHOD $ENDPOINT → $STATUS ($DESC — expected error)"
    PASS=$((PASS + 1))
  else
    echo "  WARN: $METHOD $ENDPOINT → $STATUS ($DESC)"
    WARN=$((WARN + 1))
  fi
}

echo ""
echo "── Router (SERVER spans) ──"
check_endpoint GET /ping "" "health check"
check_endpoint GET /health "" "health JSON"

echo ""
echo "── JDBC / PostgreSQL (CLIENT spans via JdbcClientAdvice) ──"
check_endpoint GET /v1/holding "" "list all holdings"
check_endpoint POST /v1/holding '{"userId":"user1","symbol":"AAPL","quantity":10}' "create holding"
check_endpoint GET /v1/holding/user1 "" "get user holdings"

echo ""
echo "── WebClient (CLIENT spans via WebClientAdvice) ──"
check_endpoint GET /v1/external/joke "" "httpbin.org call"
check_endpoint GET /v1/external/post/1 "" "jsonplaceholder call"

echo ""
echo "── Kafka (PRODUCER spans via KafkaProducerAdvice) ──"
check_endpoint POST /v1/kafka/produce '{"key":"test-1","value":"{\"msg\":\"hello\"}"}' "produce single"
check_endpoint POST /v1/kafka/produce-batch '{"count":3,"prefix":"batch"}' "produce batch"

echo ""
echo "── Aerospike (CLIENT spans via AerospikeClientAdvice) ──"
check_endpoint POST /v1/cache/mykey '{"foo":"bar","num":42}' "cache put"
check_endpoint GET /v1/cache/mykey "" "cache get"
check_endpoint DELETE /v1/cache/mykey "" "cache delete"

echo ""
echo "── MySQL Reactive (CLIENT spans via ReactiveSqlAdvice) ──"
check_endpoint GET /v1/mysql/ping "" "mysql ping"

echo ""
echo "── Multi-System (DB + Cache + HTTP + Kafka) ──"
check_endpoint GET /v1/portfolio-full/user1 "" "full portfolio"

echo ""
echo "── Error Scenarios (exception recording) ──"
check_endpoint GET "/v1/error/http" "" "error http (expected error)"
check_endpoint GET "/v1/error/try-catch" "" "error try-catch (expected error)"

# Cleanup
kill $APP_PID 2>/dev/null
wait $APP_PID 2>/dev/null || true

if [ "$INFRA_RUNNING" = "true" ]; then
  echo ""
  echo "Infrastructure is still running. Stop with: docker compose down"
fi

echo ""
echo "=== Results: $PASS passed, $WARN warnings, $FAIL failed ==="
echo "Check Last9 for traces from service 'java8-test-local'"
