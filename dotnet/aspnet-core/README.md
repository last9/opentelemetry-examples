# ASP.NET Core (.NET 6) — OTel Auto-Instrumentation

Zero-code OpenTelemetry instrumentation for ASP.NET Core (.NET 6+) applications, supporting both IIS-hosted and self-hosted (Kestrel) deployments. No OTel SDK packages in the app — traces and metrics are captured by the CLR profiler injected at the process level.

## What Gets Auto-Instrumented

| Signal | Library | What's captured |
|--------|---------|----------------|
| Trace | ASP.NET Core | Incoming request span (route, method, status) — both controllers and minimal API |
| Trace | IHttpClientFactory / HttpClient | Outbound HTTP call span + W3C `traceparent` header injection |
| Trace | ADO.NET (DbCommand) | SQL query span with `db.statement` |
| Metric | .NET CLR | GC generations, heap size, thread pool, exceptions/sec |
| Metric | IIS (IIS mode only) | Request rate, queue depth, connection count |

## Prerequisites

- .NET 6.0+ runtime installed
- **For IIS mode**: Windows Server 2016+ with IIS 8.5+, **Windows PowerShell 5.1** (Desktop edition — not PS7)
- **For Kestrel mode**: Windows (PowerShell 5.1 needed for setup only)
- Administrator access
- OTel Collector (gateway) reachable on port 4317

## Quick Start

### IIS mode (recommended for production on Windows)

**1. Run setup** (Windows PowerShell 5.1, Run as Administrator):

```powershell
.\setup-otel.ps1 `
    -Mode iis `
    -AppPoolName "YourCoreAppPool" `
    -ServiceName "your-service-name" `
    -OtlpEndpoint "http://gateway-vm:4317" `
    -DeployCollectorConfig
```

The script sets `managedRuntimeVersion = ""` (No Managed Code) on the app pool automatically — this is required for ASP.NET Core and is a common source of silent failures.

### Kestrel mode (dev / self-hosted)

**1. Run setup** to generate `otel.env`:
```powershell
powershell.exe -Version 5.1 -File setup-otel.ps1 `
    -Mode kestrel `
    -ServiceName "your-service-name" `
    -OtlpEndpoint "http://gateway-vm:4317"
```

**2. Load env vars and run**:
```powershell
Get-Content otel.env | ForEach-Object {
    $k, $v = $_ -split '=', 2
    [System.Environment]::SetEnvironmentVariable($k, $v)
}
dotnet run
```

## Project Structure

```
aspnet-core/
├── Controllers/
│   └── TodosController.cs       # Controller-based Web API
├── Data/
│   └── TodoRepository.cs        # ADO.NET + SQLite (auto-instrumented)
├── Models/
│   └── Todo.cs
├── Properties/
│   └── launchSettings.json      # IIS Express + Kestrel profiles
├── Program.cs                   # Minimal API + controller registration (no OTel code)
├── appsettings.json
├── AspNetCore.csproj            # No OTel packages
├── setup-otel.ps1               # One-shot setup (start here)
├── otelcol-dotnet.yaml          # IIS + CLR metrics collector config
└── env.example                  # OTEL_* var reference
```

## API Endpoints

Both controller-based and minimal API endpoints are instrumented identically.

| Style | Method | Path | Description |
|-------|--------|------|-------------|
| Controller | GET | `/api/todos` | List todos (DB read) |
| Controller | POST | `/api/todos` | Create todo (DB write) |
| Controller | PATCH | `/api/todos/{id}/complete` | Mark complete |
| Controller | GET | `/api/todos/upstream` | Outbound HTTP → http span |
| Minimal API | GET | `/minimal/todos` | Same as above, minimal style |
| Minimal API | POST | `/minimal/todos` | Same as above, minimal style |
| Minimal API | GET | `/minimal/upstream` | Outbound HTTP, minimal style |
| — | GET | `/health` | Health check |

## Troubleshooting

### "This script requires Windows PowerShell 5.1"

```powershell
powershell.exe -Version 5.1 -File setup-otel.ps1 -Mode iis -AppPoolName ... -ServiceName ... -OtlpEndpoint ...
```

### No spans — IIS mode

1. **Check app pool CLR version** — must be empty (No Managed Code), not `v4.0`:
   ```powershell
   (Get-ItemProperty "IIS:\AppPools\YourPool").managedRuntimeVersion
   # Must return: "" (empty string)
   # If it returns "v4.0", run: Set-ItemProperty "IIS:\AppPools\YourPool" -Name managedRuntimeVersion -Value ""
   ```

2. **Verify profiler loaded**:
   ```powershell
   Get-Process w3wp | % { $_.Modules | Where ModuleName -like "*OpenTelemetry*" }
   ```

3. **Check auto-instrumentation log**:
   ```powershell
   Get-ChildItem $env:TEMP -Filter "otel-dotnet-auto-*" | Sort LastWriteTime -Desc | Select -First 1 | Get-Content | Select -Last 30
   ```

### No spans — Kestrel mode

Verify all `CORECLR_*` and `DOTNET_*` env vars are set in the same process before `dotnet run`. Loading them in a separate shell window won't work — they must be in the same session.

### Two services showing the same `service.name`

See the shared app pool note in the Framework README. Same limitation applies — use dedicated app pools.

## Database Note

This sample uses SQLite (`Microsoft.Data.Sqlite`) for self-contained demo purposes. In production with SQL Server, replace with `Microsoft.Data.SqlClient` — SQL Server queries are auto-instrumented identically.
