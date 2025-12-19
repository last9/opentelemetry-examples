# Instrumenting gRPC-Gateway Application using OpenTelemetry

This example demonstrates how to instrument a gRPC-Gateway application with OpenTelemetry. gRPC-Gateway allows you to serve both gRPC and HTTP/JSON APIs from the same service by providing automatic transcoding between HTTP/JSON and gRPC.

## Architecture

```
HTTP Client
    ↓
HTTP Server (port 8080)
    ↓
http.ServeMux (standard library) [OTel HTTP instrumentation]
    ↓
runtime.ServeMux (grpc-gateway) [gRPC-to-JSON transcoding]
    ↓
gRPC Client [OTel gRPC client instrumentation]
    ↓
gRPC Server (port 50051) [OTel gRPC server instrumentation]
    ↓
Service Implementation
```

## What Gets Instrumented

This example demonstrates three layers of OpenTelemetry instrumentation:

1. **HTTP Layer** (`otelhttp.NewHandler`): Captures HTTP requests, response codes, and latency
2. **gRPC Client** (`otelgrpc.NewClientHandler`): Traces the gateway's calls to the gRPC server
3. **gRPC Server** (`otelgrpc.NewServerHandler`): Traces the actual gRPC method invocations

The result is complete distributed tracing across the full HTTP → gRPC stack.

## Setup

### 1. Install dependencies

```bash
go mod tidy
```

### 2. Get Last9 OTLP Credentials

Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).

### 3. Set environment variables

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
```

## Running the Example

### Option 1: Run the combined gateway server

This starts both the gRPC server and HTTP gateway in a single process:

```bash
OTEL_SERVICE_NAME=grpc-gateway-app go run gateway/main.go
```

### Option 2: Run gRPC server separately

In one terminal, start the gRPC server:

```bash
OTEL_SERVICE_NAME=grpc-server-app go run server/main.go
```

Then start just the HTTP gateway (requires modifying gateway/main.go to not start its own gRPC server).

## Testing the Service

### Using curl (HTTP/JSON)

```bash
# Test the gRPC service via HTTP
curl -X POST http://localhost:8080/v1/greeter/hello \
  -H "Content-Type: application/json" \
  -d '{"name":"World"}'

# Output: {"message":"Hello World from gRPC-Gateway!"}

# Health check
curl http://localhost:8080/health
# Output: OK
```

### Using the instrumented HTTP client

```bash
OTEL_SERVICE_NAME=grpc-gateway-client go run client/main.go World
# Output: Response: Hello World from gRPC-Gateway!
```

### Using grpcurl (direct gRPC)

If you want to test the gRPC server directly (bypassing the gateway):

```bash
# Install grpcurl if you haven't already
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# Call the service directly via gRPC
grpcurl -plaintext -d '{"name": "World"}' localhost:50051 greeter.Greeter/SayHello
```

## Viewing Traces

1. Sign in to the [Last9 Dashboard](https://app.last9.io)
2. Navigate to the APM section
3. You'll see traces showing the complete request flow:
   ```
   HTTP POST /v1/greeter/hello
     └─ gRPC greeter.Greeter/SayHello (client)
         └─ gRPC greeter.Greeter/SayHello (server)
             └─ SayHello span
   ```

## Key Files

- **`proto/greeter.proto`**: Protocol Buffer definition with HTTP annotations
- **`proto/greeter.pb.gw.go`**: Generated grpc-gateway HTTP handlers
- **`gateway/main.go`**: Combined HTTP gateway + gRPC server with full OTel instrumentation
- **`server/main.go`**: Standalone gRPC server
- **`client/main.go`**: Instrumented HTTP client example
- **`instrumentation/instrumentation.go`**: OpenTelemetry setup

## How It Works

### Proto Annotations

The `.proto` file includes HTTP annotations that tell grpc-gateway how to map HTTP routes to gRPC methods:

```protobuf
rpc SayHello (HelloRequest) returns (HelloReply) {
    option (google.api.http) = {
        post: "/v1/greeter/hello"
        body: "*"
    };
}
```

### Instrumentation Layers

```go
// 1. gRPC server with OTel
grpcServer := grpc.NewServer(
    grpc.StatsHandler(otelgrpc.NewServerHandler()),
)

// 2. gRPC client (gateway → server) with OTel
conn, _ := grpc.NewClient("localhost:50051",
    grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
)

// 3. HTTP server with OTel
handler := otelhttp.NewHandler(httpMux, "grpc-gateway-http")
```

## Benefits of gRPC-Gateway

1. **Dual Protocol Support**: Serve both gRPC and HTTP/JSON clients from one service
2. **Automatic Transcoding**: No manual HTTP handler code needed
3. **OpenAPI/Swagger**: Can generate API documentation from proto files
4. **Complete Observability**: Full distributed tracing across both protocols

## Regenerating Proto Files

If you modify the `.proto` file:

```bash
chmod +x proto/generate.sh
./proto/generate.sh
```

This will regenerate:
- `greeter.pb.go` (message types)
- `greeter_grpc.pb.go` (gRPC client/server interfaces)
- `greeter.pb.gw.go` (grpc-gateway HTTP handlers)

## Learn More

- [gRPC-Gateway Documentation](https://grpc-ecosystem.github.io/grpc-gateway/)
- [OpenTelemetry Go Documentation](https://opentelemetry.io/docs/instrumentation/go/)
- [Last9 Documentation](https://docs.last9.io/)
