#!/bin/bash

# Generate gRPC and grpc-gateway code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Regenerating protobuf code with grpc-gateway support..."

# Use buf for clean generation
cd ..

# Create buf.yaml if it doesn't exist
cat > buf.yaml <<EOF
version: v2
modules:
  - path: proto
deps:
  - buf.build/googleapis/googleapis
EOF

# Create buf.gen.yaml if it doesn't exist
cat > buf.gen.yaml <<EOF
version: v2
managed:
  enabled: true
plugins:
  - remote: buf.build/protocolbuffers/go
    out: proto
    opt: paths=source_relative
  - remote: buf.build/grpc/go
    out: proto
    opt: paths=source_relative
  - remote: buf.build/grpc-ecosystem/gateway
    out: proto
    opt:
      - paths=source_relative
      - generate_unbound_methods=true
EOF

# Fetch dependencies
~/go/bin/buf dep update

# Generate using buf
~/go/bin/buf generate proto

echo "✓ Generated files:"
echo "  - proto/greeter.pb.go (protobuf messages)"
echo "  - proto/greeter_grpc.pb.go (gRPC server/client)"
echo "  - proto/greeter.pb.gw.go (grpc-gateway HTTP proxy)"
