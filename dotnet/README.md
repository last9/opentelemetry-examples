# .NET 8.0+ Application Auto-Instrumentation with OpenTelemetry and Last9

This guide explains how to use OpenTelemetry auto-instrumentation with .NET 8.0+ applications to send traces to Last9. This approach requires **zero code changes** to your existing application.

## Prerequisites

- .NET 8.0 or later
- Linux/macOS/Windows environment

## Installation

1. Install the OpenTelemetry .NET Auto-Instrumentation agent:

**Linux/macOS:**
```bash
# Download and install the auto-instrumentation agent
curl -sSfL https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/otel-dotnet-auto-install.sh -O
chmod +x otel-dotnet-auto-install.sh
./otel-dotnet-auto-install.sh
```

**Windows (PowerShell):**
```powershell
# Download and install the auto-instrumentation agent
Invoke-WebRequest -Uri "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/otel-dotnet-auto-install.ps1" -OutFile "otel-dotnet-auto-install.ps1"
.\otel-dotnet-auto-install.ps1
```

2. Verify the installation:

**Linux/macOS:**
```bash
ls -la $HOME/.otel-dotnet-auto/instrument.sh
```

**Windows:**
```powershell
Get-ChildItem "$env:USERPROFILE\.otel-dotnet-auto\instrument.cmd"
```

## Usage

1. **No code changes required!** Your existing .NET application works as-is.

2. **Your project file remains minimal** - no OpenTelemetry packages required:

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
```

3. **Set the following environment variables**:

**Linux/macOS:**
```bash
export OTEL_DOTNET_AUTO_INSTRUMENTATION_ENABLED=true
export OTEL_SERVICE_NAME="<your_service_name>"
export OTEL_TRACES_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_ENDPOINT="<last9_otel_endpoint>"
export OTEL_EXPORTER_OTLP_HEADERS="<last9_auth_header>"
export OTEL_TRACES_SAMPLER="always_on"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
export OTEL_LOG_LEVEL=debug
```

**Windows:**
```powershell
$env:OTEL_DOTNET_AUTO_INSTRUMENTATION_ENABLED="true"
$env:OTEL_SERVICE_NAME="<your_service_name>"
$env:OTEL_TRACES_EXPORTER="otlp"
$env:OTEL_EXPORTER_OTLP_ENDPOINT="<last9_otel_endpoint>"
$env:OTEL_EXPORTER_OTLP_HEADERS="<last9_auth_header>"
$env:OTEL_TRACES_SAMPLER="always_on"
$env:OTEL_RESOURCE_ATTRIBUTES="deployment.environment=production"
$env:OTEL_LOG_LEVEL=debug
```

4. **Start your application with instrumentation**:

**Linux/macOS:**
```bash
# Source the instrumentation and run
. $HOME/.otel-dotnet-auto/instrument.sh
dotnet run
```

**Windows:**
```cmd
call "%USERPROFILE%\.otel-dotnet-auto\instrument.cmd"
dotnet run
```

5. **Run your application and see the traces in Last9** [Trace Explorer](https://app.last9.io/traces).

## Features

### Automatic Instrumentation

The following operations are automatically instrumented **without any code changes**:

1. **HTTP Operations (ASP.NET Core)**:
```csharp
// Automatically traced
app.MapGet("/api/endpoint", () => "Response");
app.MapPost("/api/data", (DataModel data) => Results.Created());
```

2. **Database Operations**:
```csharp
// Entity Framework - automatically traced
var users = await context.Users.ToListAsync();

// SQL Client - automatically traced
using var connection = new SqlConnection(connectionString);
var result = await connection.QueryAsync<User>("SELECT * FROM Users");
```

3. **HTTP Client Operations**:
```csharp
// HttpClient - automatically traced
var client = new HttpClient();
var response = await client.GetAsync("https://api.example.com/data");
```

4. **Message Queue Operations**:
```csharp
// RabbitMQ, Azure Service Bus - automatically traced
await serviceBusClient.SendMessageAsync(message);
```

5. **Cache Operations**:
```csharp
// Redis, MemoryCache - automatically traced
await cache.SetStringAsync("key", "value");
```

### Logging Integration

All `ILogger` calls are automatically correlated with traces:

```csharp
public class UserService
{
    private readonly ILogger<UserService> _logger;
    
    public async Task<User> GetUserAsync(int id)
    {
        // This log will be correlated with the active trace
        _logger.LogInformation("Fetching user {UserId}", id);
        
        // Database call is automatically traced
        return await _context.Users.FindAsync(id);
    }
}
```

### Error Handling

The instrumentation automatically captures:
- **HTTP errors** (4xx, 5xx status codes)
- **Database errors** (connection failures, query timeouts)
- **HTTP client errors** (network timeouts, DNS failures)
- **Unhandled exceptions** with full stack traces
- **Custom logged errors** via `ILogger.LogError()`

Each error includes:
- Exception message and type
- Stack trace
- Request context and attributes
- Timing information

## How It Works

The auto-instrumentation:
1. **Injects at runtime** using .NET's profiling API - no code changes needed
2. **Creates spans automatically** for HTTP requests with format `HTTP METHOD /endpoint`
3. **Instruments popular libraries** (Entity Framework, HttpClient, SQL Client, etc.)
4. **Propagates context** through async/await chains automatically
5. **Correlates logs** with active traces using trace context
6. **Handles errors** and sets appropriate span statuses
7. **Sends traces** to Last9's OpenTelemetry endpoint in batches

## Support

For issues or questions:
- Check [Last9 documentation](https://docs.last9.io)
- Contact Last9 support
- Review [OpenTelemetry .NET documentation](https://opentelemetry.io/docs/instrumentation/net/)
