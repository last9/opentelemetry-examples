#!/bin/bash

# Setup script for gRPC-Gateway demo with PostgreSQL

set -e

echo "🚀 Setting up gRPC-Gateway demo environment..."
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running. Please start Docker and try again."
    exit 1
fi

echo "✓ Docker is running"

# Start PostgreSQL
echo ""
echo "Starting PostgreSQL container..."
docker-compose up -d postgres

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker-compose exec -T postgres pg_isready -U grpc_user -d grpc_gateway > /dev/null 2>&1; then
        echo "✓ PostgreSQL is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ PostgreSQL failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

echo ""
echo "✅ Setup complete!"
echo ""
echo "Database connection details:"
echo "  Host: localhost"
echo "  Port: 5432"
echo "  Database: grpc_gateway"
echo "  User: grpc_user"
echo "  Password: grpc_pass"
echo ""
echo "Connection string:"
echo "  DATABASE_URL=\"postgres://grpc_user:grpc_pass@localhost:5432/grpc_gateway?sslmode=disable\""
echo ""
echo "To stop PostgreSQL:"
echo "  docker-compose down"
echo ""
echo "To view logs:"
echo "  docker-compose logs -f postgres"
