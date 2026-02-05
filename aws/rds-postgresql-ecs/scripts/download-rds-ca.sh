#!/bin/bash
# Download RDS CA bundle for TLS connections

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
CA_BUNDLE_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
CA_BUNDLE_FILE="${CONFIG_DIR}/rds-combined-ca-bundle.pem"

echo "Downloading RDS CA bundle..."

# Create config directory if it doesn't exist
mkdir -p "${CONFIG_DIR}"

# Download the CA bundle
if command -v curl &> /dev/null; then
    curl -sS -o "${CA_BUNDLE_FILE}" "${CA_BUNDLE_URL}"
elif command -v wget &> /dev/null; then
    wget -q -O "${CA_BUNDLE_FILE}" "${CA_BUNDLE_URL}"
else
    echo "Error: Neither curl nor wget is available"
    exit 1
fi

# Verify the download
if [ -f "${CA_BUNDLE_FILE}" ] && [ -s "${CA_BUNDLE_FILE}" ]; then
    echo "Successfully downloaded RDS CA bundle to: ${CA_BUNDLE_FILE}"
    echo "File size: $(wc -c < "${CA_BUNDLE_FILE}") bytes"
else
    echo "Error: Failed to download RDS CA bundle"
    exit 1
fi

# Verify it's a valid PEM file
if head -1 "${CA_BUNDLE_FILE}" | grep -q "BEGIN CERTIFICATE"; then
    echo "CA bundle verification: OK"
else
    echo "Warning: CA bundle may not be valid PEM format"
fi

echo "Done!"
