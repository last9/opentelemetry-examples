# ASP.NET Core + OpenTelemetry + Last9

A minimal ASP.NET Core 8 API instrumented with OpenTelemetry, sending traces, metrics, and logs to Last9.

## Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8)
- Last9 account — get your OTLP endpoint and credentials from the [Last9 dashboard](https://app.last9.io)

## Quick Start

1. **Copy and fill in credentials:**

```bash
cp .env.example .env
```

Edit `.env`:

```env
OTEL_SERVICE_NAME=last9-csharp-example
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <base64(username:password)>
```

Generate your Base64 credentials:

```bash
echo -n "your-username:your-last9-write-token" | base64
```

2. **Run:**

```bash
export $(cat .env | xargs) && dotnet run
```

3. **Send test requests:**

```bash
curl http://localhost:5000/orders
curl http://localhost:5000/orders/1
curl -X POST http://localhost:5000/orders \
  -H "Content-Type: application/json" \
  -d '{"product":"Widget","amount":99.99}'
```

4. **View in Last9:** [app.last9.io/traces](https://app.last9.io/traces) — filter by service name `last9-csharp-example`.

## Configuration

| Variable | Description | Default |
|---|---|---|
| `OTEL_SERVICE_NAME` | Service name shown in Last9 | `last9-csharp-example` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint | `https://otlp.last9.io` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth header (`Authorization=Basic <base64>`) | — |
| `DEPLOYMENT_ENVIRONMENT` | Environment resource attribute | `production` |

## What's Instrumented

**Traces:**
- HTTP server spans — every inbound request via `AddAspNetCoreInstrumentation`
- HTTP client spans — outbound `HttpClient` calls via `AddHttpClientInstrumentation`
- Custom spans — manual spans via `ActivitySource.StartActivity(...)`

**Metrics:**
- HTTP server metrics — request count, duration, error rate
- HTTP client metrics — outbound call metrics
- .NET runtime metrics — GC collections, heap size, thread pool via `AddRuntimeInstrumentation`
- Custom counters — `orders.created`, `orders.listed`

**Logs:**
- All `ILogger` output exported to Last9 via OTLP, correlated with active trace

## Key Configuration Details

```csharp
// Protocol MUST be explicitly set — .NET defaults to gRPC,
// but Last9's /v1/traces endpoint expects HTTP/Protobuf
options.Protocol = OtlpExportProtocol.HttpProtobuf;

// ForceFlush prevents span/metric loss on graceful shutdown
app.Lifetime.ApplicationStopping.Register(() =>
{
    app.Services.GetRequiredService<TracerProvider>().ForceFlush(5000);
    app.Services.GetRequiredService<MeterProvider>().ForceFlush(5000);
});
```

## Troubleshooting

**Spans not appearing in Last9:**

1. Verify credentials — check the Authorization header is correct Base64
2. Check the OTLP endpoint responds: `curl -I https://otlp.last9.io`
3. Debug exporter by temporarily pointing at [webhook.site](https://webhook.site):
   ```
   OTEL_EXPORTER_OTLP_ENDPOINT=https://webhook.site/<your-unique-id>
   ```
   If POST requests arrive at webhook.site, the exporter works and the issue is credentials.

## Docker

```bash
docker build -t last9-csharp-example .
docker run -p 8080:8080 \
  -e OTEL_SERVICE_NAME=last9-csharp-example \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io \
  -e OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64-creds>" \
  -e DEPLOYMENT_ENVIRONMENT=production \
  last9-csharp-example
```
