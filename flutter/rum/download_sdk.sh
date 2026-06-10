#!/usr/bin/env bash
#
# Downloads, checksum-verifies and extracts the Last9 RUM Flutter SDK into the
# git-ignored vendor/ directory. The SDK is distributed as a CDN tarball and is
# NOT committed to this repo. Run this once before `flutter pub get`.
#
# Usage: ./download_sdk.sh                 # downloads the default version
#        LAST9_RUM_VERSION=0.8.0 ./download_sdk.sh   # override the version
#
# CDN tarball URL pattern (see the SDK README):
#   https://cdn.last9.io/rum-sdk/flutter/builds/<version>/last9_rum_flutter-<version>.tar.gz
#
set -euo pipefail

VERSION="${LAST9_RUM_VERSION:-0.7.1}"
BASE_URL="https://cdn.last9.io/rum-sdk/flutter/builds/${VERSION}"
TARBALL="last9_rum_flutter-${VERSION}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Downloading Last9 RUM Flutter SDK v${VERSION}..."
curl -fL -o "$TARBALL" "${BASE_URL}/${TARBALL}"

echo "Verifying checksum..."
EXPECTED="$(curl -fsL "${BASE_URL}/${TARBALL}.sha256" | awk '{print $1}')"
ACTUAL="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"

if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "CHECKSUM MISMATCH"
  echo "  expected: $EXPECTED"
  echo "  actual:   $ACTUAL"
  rm -f "$TARBALL"
  exit 1
fi
echo "Checksum OK"

echo "Extracting into vendor/..."
rm -rf vendor
mkdir -p vendor
tar xzf "$TARBALL" -C vendor/
rm -f "$TARBALL"

echo "Done. vendor/flutter is ready. Next: flutter pub get"
