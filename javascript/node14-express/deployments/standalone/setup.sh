#!/bin/bash
# =============================================================================
# Standalone OTel Collector Setup (No Docker/K8s)
# =============================================================================
#
# Installs the OpenTelemetry Collector as a systemd service on Linux.
# The collector runs alongside your Node.js application.
#
# Prerequisites:
# - Linux with systemd
# - curl and tar installed
# - sudo access
#
# Usage:
#   sudo ./setup.sh install    # Install collector
#   sudo ./setup.sh uninstall  # Remove collector
#   ./setup.sh status          # Check status

set -e

COLLECTOR_VERSION="0.118.0"
INSTALL_DIR="/opt/otel-collector"
CONFIG_DIR="/etc/otel-collector"
SERVICE_USER="otel"

install_collector() {
    echo "Installing OpenTelemetry Collector ${COLLECTOR_VERSION}..."

    # Detect architecture
    ARCH=$(uname -m)
    case ${ARCH} in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
    esac

    # Create service user
    if ! id -u ${SERVICE_USER} &>/dev/null; then
        useradd --system --no-create-home ${SERVICE_USER}
    fi

    # Create directories
    mkdir -p ${INSTALL_DIR} ${CONFIG_DIR}

    # Download collector
    DOWNLOAD_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${COLLECTOR_VERSION}/otelcol-contrib_${COLLECTOR_VERSION}_linux_${ARCH}.tar.gz"
    echo "Downloading from ${DOWNLOAD_URL}..."
    curl -sL "${DOWNLOAD_URL}" | tar -xzf - -C ${INSTALL_DIR}

    # Copy config
    cp "$(dirname "$0")/otel-collector-config.yaml" ${CONFIG_DIR}/config.yaml
    chown -R ${SERVICE_USER}:${SERVICE_USER} ${CONFIG_DIR}

    # Create environment file for credentials
    cat > ${CONFIG_DIR}/collector.env << 'EOF'
# Last9 credentials - update these values
LAST9_OTLP_ENDPOINT=https://otlp.last9.io
LAST9_AUTH_HEADER=Basic YOUR_TOKEN_HERE
EOF
    chmod 600 ${CONFIG_DIR}/collector.env

    # Create systemd service
    cat > /etc/systemd/system/otel-collector.service << EOF
[Unit]
Description=OpenTelemetry Collector
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
EnvironmentFile=${CONFIG_DIR}/collector.env
ExecStart=${INSTALL_DIR}/otelcol-contrib --config=${CONFIG_DIR}/config.yaml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable otel-collector
    systemctl start otel-collector

    echo ""
    echo "Installation complete!"
    echo ""
    echo "IMPORTANT: Update credentials in ${CONFIG_DIR}/collector.env"
    echo "Then restart: sudo systemctl restart otel-collector"
    echo ""
    echo "Configure your app to use:"
    echo "  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318"
}

uninstall_collector() {
    echo "Uninstalling OpenTelemetry Collector..."

    systemctl stop otel-collector 2>/dev/null || true
    systemctl disable otel-collector 2>/dev/null || true
    rm -f /etc/systemd/system/otel-collector.service
    systemctl daemon-reload

    rm -rf ${INSTALL_DIR}
    rm -rf ${CONFIG_DIR}

    userdel ${SERVICE_USER} 2>/dev/null || true

    echo "Uninstallation complete"
}

show_status() {
    systemctl status otel-collector --no-pager
}

case "${1:-}" in
    install)
        if [ "$EUID" -ne 0 ]; then
            echo "Please run with sudo: sudo $0 install"
            exit 1
        fi
        install_collector
        ;;
    uninstall)
        if [ "$EUID" -ne 0 ]; then
            echo "Please run with sudo: sudo $0 uninstall"
            exit 1
        fi
        uninstall_collector
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {install|uninstall|status}"
        echo ""
        echo "  install   - Install collector as systemd service (requires sudo)"
        echo "  uninstall - Remove collector (requires sudo)"
        echo "  status    - Check collector status"
        exit 1
        ;;
esac
