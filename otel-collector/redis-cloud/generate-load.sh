#!/bin/bash
# Generates Redis load to produce meaningful metrics for testing

REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
CLI="redis-cli -h $REDIS_HOST -p $REDIS_PORT"

echo "Seeding keys..."
for i in $(seq 1 1000); do
  $CLI SET "key:$i" "value:$i" EX 300 > /dev/null
done

echo "Seeding hashes..."
for i in $(seq 1 200); do
  $CLI HSET "user:$i" name "user$i" email "user$i@example.com" score "$((RANDOM % 1000))" > /dev/null
done

echo "Seeding lists..."
for i in $(seq 1 100); do
  $CLI RPUSH "queue:$i" "job1" "job2" "job3" > /dev/null
done

echo "Generating keyspace hits..."
for i in $(seq 1 800); do
  $CLI GET "key:$i" > /dev/null
done

echo "Generating keyspace misses..."
for i in $(seq 2000 2200); do
  $CLI GET "key:$i" > /dev/null
done

echo "Triggering key expiry (short TTL)..."
for i in $(seq 1 50); do
  $CLI SET "expire:$i" "temp" EX 1 > /dev/null
done
sleep 2

echo "Load generation complete."
$CLI INFO stats | grep -E "keyspace_hits|keyspace_misses|expired_keys|evicted_keys"
