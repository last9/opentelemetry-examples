# .NET HTTP Body Capture with OTel Auto-Instrumentation

Capture HTTP request/response bodies as trace span attributes using a NuGet package. Redact HIPAA PHI centrally via an OTel Collector gateway.

## Architecture

```
┌─────────────┐     OTLP      ┌──────────────────┐     OTLP      ┌─────────┐
│  .NET App   │ ────────────> │  OTel Collector   │ ────────────> │  Last9  │
│             │               │  (Gateway)        │               │         │
│ NuGet pkg   │               │ transform/        │               │         │
│ captures    │               │ redact-phi        │               │         │
│ bodies as   │               │ masks SSN, email, │               │         │
│ span attrs  │               │ phone, DOB, etc.  │               │         │
└─────────────┘               └──────────────────┘               └─────────┘
```

## Prerequisites

- Docker and Docker Compose
- [Last9 OTLP credentials](https://app.last9.io)

## Adding to Your App

**Step 1:** Install the package:

```bash
dotnet add package Last9.OpenTelemetry.BodyCapture
```

**Step 2:** One line in `Program.cs`:

```csharp
builder.Services.AddHttpBodyCapture(builder.Configuration);
```

**Step 3:** Add config to `appsettings.json`:

```json
{
  "BodyCapture": {
    "Enabled": true,
    "CaptureRequestBody": true,
    "CaptureResponseBody": true,
    "MaxBodySizeBytes": 8192,
    "CaptureOnErrorOnly": false,
    "ExcludePaths": ["/health", "/ready", "/metrics"]
  }
}
```

That's it. The middleware auto-registers via `IStartupFilter` — no `app.UseMiddleware<...>()` needed.

## Quick Start (Demo)

1. Configure credentials:
   ```bash
   cp .env.example .env
   # Edit .env with your Last9 OTLP endpoint and auth
   ```

2. Start the stack:
   ```bash
   docker compose up --build
   ```

3. Send test requests:
   ```bash
   curl http://localhost:8080/api/patients/123
   curl -X POST http://localhost:8080/api/patients \
     -H "Content-Type: application/json" \
     -d '{"name":"John Smith","ssn":"111-22-3333","email":"john@example.com"}'
   ```

4. Check traces in [Last9](https://app.last9.io) — bodies appear as span attributes with PHI redacted.

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `Enabled` | `true` | Master switch |
| `CaptureRequestBody` | `true` | Capture incoming request bodies |
| `CaptureResponseBody` | `true` | Capture outgoing response bodies |
| `MaxBodySizeBytes` | `8192` | Max body size before truncation |
| `CaptureOnErrorOnly` | `false` | Only capture on 4xx/5xx responses |
| `ContentTypes` | `["application/json", ...]` | Content types to capture |
| `IncludePaths` | `[]` | Path prefixes to include (empty = all) |
| `ExcludePaths` | `["/health", "/ready", "/metrics"]` | Path prefixes to skip |

### Production recommendation

```json
{
  "BodyCapture": {
    "CaptureOnErrorOnly": true,
    "ExcludePaths": ["/health", "/ready", "/metrics", "/swagger"]
  }
}
```

## PHI Redaction (HIPAA)

The OTel Collector's `transform/redact-phi` processor masks these patterns **before** data leaves your infrastructure:

| PHI Type | Example Input | Redacted Output |
|----------|--------------|-----------------|
| SSN | `123-45-6789` | `***-**-****` |
| Email | `jane@example.com` | `****@****.***` |
| Phone | `555-123-4567` | `***-***-****` |
| DOB (ISO) | `1985-03-15` | `****-**-**` |
| DOB (US) | `03/15/1985` | `**/**/****` |
| ZIP+4 | `62704-1234` | `*****-****` |
| Credit Card | `4111-1111-1111-1111` | `****-****-****-****` |

Add custom patterns to `otel-collector-config.yaml` under `transform/redact-phi` → `statements`.

## How It Works

1. **Auto-instrumentation** — The OTel .NET agent (CLR profiler) automatically creates spans for HTTP requests. No OTel SDK code needed.

2. **Body capture** — The NuGet package auto-registers middleware via `IStartupFilter` that adds `http.request.body` and `http.response.body` as span attributes.

3. **Centralized redaction** — The OTel Collector gateway applies `replace_pattern` OTTL transforms to mask PHI before forwarding to Last9.

## Project Structure

```
├── src/Last9.OpenTelemetry.BodyCapture/   # NuGet package source
│   ├── BodyCapture.cs                      # Options, middleware, extension method
│   └── Last9.OpenTelemetry.BodyCapture.csproj
├── example/                                # Demo app
│   ├── Program.cs
│   ├── ExampleApp.csproj
│   └── appsettings.json
├── otel-collector-config.yaml              # Collector with PHI redaction
└── docker-compose.yaml
```

## Verification

After sending requests, check that:
- Spans in Last9 have `http.request.body` and `http.response.body` attributes
- PHI values (SSN, email, phone, DOB) are masked with `****` patterns
- Health/metrics endpoints do NOT have body attributes
