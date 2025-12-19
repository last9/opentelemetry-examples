#!/bin/bash

# Generate gRPC and grpc-gateway code using buf

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Fetching protobuf dependencies..."
~/go/bin/buf dep update

echo "Generating protobuf code..."
~/go/bin/buf generate proto

echo ""
echo "✓ Code generation completed successfully!"
echo ""
echo "Generated files:"
echo "  - proto/greeter.pb.go (protobuf messages)"
echo "  - proto/greeter_grpc.pb.go (gRPC server/client)"
echo "  - proto/greeter.pb.gw.go (grpc-gateway HTTP proxy)"
