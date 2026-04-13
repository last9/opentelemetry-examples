# ASP.NET Framework 4.x — OTel Auto-Instrumentation

Zero-code OpenTelemetry instrumentation for ASP.NET Framework 4.6.2–4.8 applications hosted on IIS. No OTel SDK packages in the app — traces and metrics are captured by the CLR profiler injected at the IIS process level.

## What Gets Auto-Instrumented

| Signal | Library | What's captured |
|--------|---------|----------------|
| Trace | ASP.NET MVC | Incoming MVC request span (controller, action, status) |
| Trace | ASP.NET Web API | Incoming Web API request span |
| Trace | System.Net.Http.HttpClient | Outbound HTTP call span + W3C `traceparent` header injection |
| Trace | ADO.NET (DbCommand) | SQL query span with `db.statement` |
| Metric | .NET CLR | GC generations, heap size, thread count, exceptions/sec |
| Metric | IIS | Request rate, queue depth, connection count, error rate |

## Prerequisites

- Windows Server 2016+ with IIS 8.5+
- .NET Framework 4.6.2–4.8 installed
- **Windows PowerShell 5.1** (Desktop edition — not PowerShell 7)
- Administrator access on the server
- OTel Collector (gateway) reachable from this server on port 4317

## Quick Start

**1. Run the one-shot setup script** (Windows PowerShell 5.1, Run as Administrator):

```powershell
.\setup-otel.ps1 `
    -AppPoolName "YourAppPool" `
    -ServiceName "your-service-name" `
    -OtlpEndpoint "http://gateway-vm:4317" `
    -DeployCollectorConfig
```

That's it. The script:
- Downloads and installs the OTel .NET CLR profiler
- Registers it for IIS (restarts IIS automatically)
- Sets all `OTEL_*` env vars on the app pool
- Deploys `otelcol-dotnet.yaml` for IIS + CLR metrics

**2. Make a request** to your application.

**3. Verify** traces appear in Last9 → Traces, filtered by `service.name = your-service-name`.

## Project Structure

```
aspnet-framework/
├── Controllers/
│   ├── TodosController.cs   # Web API — GET/POST todos + outbound HTTP
│   └── HomeController.cs    # MVC — index page + outbound HTTP
├── Data/
│   └── TodoRepository.cs    # ADO.NET + SQLite (auto-instrumented)
├── Models/
│   └── Todo.cs
├── App_Start/
│   ├── WebApiConfig.cs
│   └── RouteConfig.cs
├── Views/Home/Index.cshtml
├── Global.asax / Global.asax.cs
├── Web.config
├── AspNetFramework.csproj
├── setup-otel.ps1           # One-shot setup (start here)
├── otelcol-dotnet.yaml      # IIS + CLR metrics collector config
└── env.example              # OTEL_* var reference
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/todos` | List todos (DB read → db span) |
| POST | `/api/todos` | Create todo (DB write → db span) |
| PATCH | `/api/todos/{id}/complete` | Mark complete (DB write) |
| GET | `/api/todos/upstream` | Outbound HTTP call to httpbin.org → http span |
| GET | `/` | MVC index — renders todos from DB |
| GET | `/home/upstream` | MVC outbound HTTP call |

## Configuration

All configuration is via `OTEL_*` environment variables set on the IIS app pool by `setup-otel.ps1`. See `env.example` for the full reference.

Key parameters:

| Variable | Description |
|----------|-------------|
| `OTEL_SERVICE_NAME` | Service name in traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Collector endpoint (gateway or Last9 direct) |
| `OTEL_TRACES_SAMPLER_ARG` | Sampling rate (1.0 = 100%, 0.1 = 10%) |

## Troubleshooting

### "This script requires Windows PowerShell 5.1"

You're running PowerShell 7. Use:
```powershell
powershell.exe -Version 5.1 -File setup-otel.ps1 -AppPoolName ... -ServiceName ... -OtlpEndpoint ...
```

### No spans appearing after setup

1. Verify the profiler loaded in the w3wp process:
   ```powershell
   Get-Process w3wp | % { $_.Modules | Where ModuleName -like "*OpenTelemetry*" }
   ```
   You should see `OpenTelemetry.AutoInstrumentation.Native`. If not, re-run `Register-OpenTelemetryForIIS`.

2. Check the auto-instrumentation log:
   ```powershell
   Get-ChildItem $env:TEMP -Filter "otel-dotnet-auto-*" | Sort LastWriteTime -Desc | Select -First 1 | Get-Content | Select -Last 30
   ```

3. Verify app pool env vars were set:
   ```powershell
   (Get-ItemProperty "IIS:\AppPools\YourAppPool").environmentVariables.Collection | Select name, value
   ```

### Two services showing the same `service.name` (shared app pool)

This is a known OTel limitation: when multiple apps share an app pool, the first app's Web.config OTEL_* settings win for the entire pool.

**Fix:** Give each service its own dedicated app pool:
```powershell
Import-Module WebAdministration
New-WebAppPool -Name "ServiceAPool"
New-WebAppPool -Name "ServiceBPool"
Set-ItemProperty "IIS:\Sites\ServiceA" -Name applicationPool -Value "ServiceAPool"
Set-ItemProperty "IIS:\Sites\ServiceB" -Name applicationPool -Value "ServiceBPool"
```
Then run `setup-otel.ps1` once per pool with its own `-ServiceName`.

### Missing Visual C++ Redistributable error

```
HRESULT: 0x80004005 — profiler failed to attach
```

Install: https://aka.ms/vs/17/release/vc_redist.x64.exe, then re-run `Register-OpenTelemetryForIIS`.

### SQL query spans not appearing

Verify you are using a provider that inherits from `System.Data.Common.DbCommand` (SqlClient, SQLite, Npgsql all do). Custom ORMs that bypass ADO.NET will not produce spans automatically.

## Database Note

This sample uses SQLite (`System.Data.SQLite`) for self-contained demo purposes. In production with SQL Server, replace `SQLiteConnection` with `SqlConnection` (`Microsoft.Data.SqlClient`) — SQL Server queries are auto-instrumented identically.
