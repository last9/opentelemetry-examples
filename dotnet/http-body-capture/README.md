# .NET HTTP Body Capture with OTel Auto-Instrumentation

Capture HTTP request/response bodies as span attributes using .NET auto-instrumentation and redact HIPAA PHI centrally via an OTel Collector gateway.

## Architecture

```
┌─────────────┐     OTLP      ┌──────────────────┐     OTLP      ┌─────────┐
│  .NET App   │ ────────────> │  OTel Collector   │ ────────────> │  Last9  │
│             │               │  (Gateway)        │               │         │
│ Middleware  │               │ transform/        │               │         │
│ captures    │               │ redact-phi        │               │         │
│ bodies as   │               │ masks SSN, email, │               │         │
│ span attrs  │               │ phone, DOB, etc.  │               │         │
└─────────────┘               └──────────────────┘               └─────────┘
```

**App-level:** Middleware adds `http.request.body` and `http.response.body` as span attributes.
**Collector-level:** `transform` processor applies regex-based PHI redaction before export.

## Prerequisites

- Docker and Docker Compose
- [Last9 OTLP credentials](https://app.last9.io)

## Quick Start

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
   # GET — response body contains PHI
   curl http://localhost:8080/api/patients/123

   # POST — request body contains PHI
   curl -X POST http://localhost:8080/api/patients \
     -H "Content-Type: application/json" \
     -d '{"name":"John Smith","ssn":"111-22-3333","email":"john@example.com"}'

   # GET — medication order with PHI
   curl http://localhost:8080/api/orders/456
   ```

4. Check traces in [Last9](https://app.last9.io) — bodies appear as span attributes with PHI redacted.

## Configuration

All body capture settings are in `appsettings.json` under the `BodyCapture` section:

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

For production, set `CaptureOnErrorOnly: true` to only capture bodies on failures — this reduces data volume while preserving the debugging value:

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

1. **Auto-instrumentation** — The OTel .NET agent (installed in the Dockerfile via CLR profiler) automatically creates spans for ASP.NET Core requests, HttpClient calls, and more. No OTel SDK code needed in the app.

2. **Body capture middleware** — `HttpBodyCaptureMiddleware` reads request/response streams and adds them as attributes (`http.request.body`, `http.response.body`) to the current `Activity` (span).

3. **Centralized redaction** — The OTel Collector gateway applies `replace_pattern` OTTL transforms to mask PHI in body attributes before forwarding to Last9.

## Adding to Your App

**Step 1:** Copy `BodyCapture.cs` into your project.

**Step 2:** Add one line to `Program.cs`:

```csharp
builder.Services.AddHttpBodyCapture(builder.Configuration);
```

**Step 3:** Add the `BodyCapture` section to your `appsettings.json`.

That's it. The middleware auto-registers via `IStartupFilter` — no `app.UseMiddleware<...>()` needed. Set up auto-instrumentation in your Dockerfile and the OTel Collector handles PII redaction centrally.

## Verification

After sending requests, check that:
- Spans in Last9 have `http.request.body` and `http.response.body` attributes
- PHI values (SSN, email, phone, DOB) are masked with `****` patterns
- Health/metrics endpoints do NOT have body attributes
