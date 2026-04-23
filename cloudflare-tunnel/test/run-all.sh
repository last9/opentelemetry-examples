#!/bin/bash
set -e

# Generate machine ID
if [ ! -s /etc/machine-id ]; then
    dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' > /etc/machine-id
fi
echo "Machine ID: $(cat /etc/machine-id)"

# Create dirs for persistent journal storage
MACHINE_ID=$(cat /etc/machine-id)
mkdir -p /run/systemd/journal
mkdir -p /var/log/journal/${MACHINE_ID}

# Start journald
echo "[1/3] Starting systemd-journald..."
/lib/systemd/systemd-journald &
JOURNALD_PID=$!

# Wait for socket
until [ -S /run/systemd/journal/socket ]; do sleep 1; done
echo "      journald ready."

# Start otelcol
echo "[2/3] Starting otelcol..."
otelcol-contrib --config=/etc/otelcol-contrib/config.yaml &
OTELCOL_PID=$!
sleep 2

# Start cloudflared — pipe through systemd-cat so output lands in journal
# with SYSLOG_IDENTIFIER=cloudflared and PRIORITY=6 (matching real-world behavior)
echo "[3/3] Starting cloudflared hello-world tunnel..."
cloudflared tunnel --hello-world 2>&1 | \
    systemd-cat --identifier=cloudflared --priority=6 &
CF_PID=$!

echo "All processes running. Waiting..."
wait $CF_PID
echo "cloudflared exited — shutting down."
kill $OTELCOL_PID $JOURNALD_PID 2>/dev/null || true
