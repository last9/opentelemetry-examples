# OpenTelemetry .NET Integration Guide

Simple steps to add observability to your .NET application and send traces to Last9.

## 🚀 Quick Setup (5 Minutes)

### Step 1: Add Packages
```bash
dotnet add package OpenTelemetry
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

### Step 2: Add Code to Your App

**For Console Apps** (add to `Program.cs`):
```csharp
using System.Diagnostics;
using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Resources;

var serviceName = Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME") ?? "MyApp";

using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService(serviceName))
    .AddSource("MyApp")
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri(Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT") ?? "https://otlp-aps1.last9.io:443");
        var headers = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS");
        if (!string.IsNullOrEmpty(headers))
            options.Headers = headers;
    })
    .Build();

// Your app code here
var activitySource = new ActivitySource("MyApp");
using (var activity = activitySource.StartActivity("MyOperation"))
{
    activity?.SetTag("app.name", serviceName);
    Console.WriteLine("Hello from my traced app!");
}
```

**For Web APIs** (add to `Program.cs`):
```csharp
using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Resources;

var builder = WebApplication.CreateBuilder(args);

// Add OpenTelemetry
var serviceName = Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME") ?? "MyWebApi";
builder.Services.AddOpenTelemetry()
    .WithTracing(tracerProviderBuilder =>
    {
        tracerProviderBuilder
            .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService(serviceName))
            .AddSource("MyWebApi")
            .AddAspNetCoreInstrumentation()
            .AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri(Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT") ?? "https://otlp-aps1.last9.io:443");
                var headers = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS");
                if (!string.IsNullOrEmpty(headers))
                    options.Headers = headers;
            });
    });

builder.Services.AddControllers();
var app = builder.Build();
app.MapControllers();
app.Run();

// For custom tracing in controllers
public static class Telemetry
{
    public static readonly ActivitySource ActivitySource = new("MyWebApi");
}
```

### Step 3: Set Environment Variables
```bash
export OTEL_SERVICE_NAME="your-app-name"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp-aps1.last9.io:443"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_LAST9_TOKEN"
```

### Step 4: Run Your App
```bash
dotnet run
```

## 🎯 That's It!

Your app now sends traces to Last9. Check your Last9 dashboard to see the telemetry data.

## 🔧 Custom Tracing

Add custom traces anywhere in your code:
```csharp
var activitySource = new ActivitySource("MyApp");

using (var activity = activitySource.StartActivity("CustomOperation"))
{
    activity?.SetTag("user.id", "12345");
    activity?.SetTag("operation.type", "database");
    
    // Your business logic here
    await DoSomething();
    
    activity?.SetStatus(ActivityStatusCode.Ok, "Operation completed");
}
```

## 🔒 Security Note

**Never commit real tokens!** Use environment variables:
```bash
# Set your token securely
export LAST9_TOKEN="your-real-token"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $LAST9_TOKEN"
```

## 🆘 Troubleshooting

**No traces appearing?**
- Check your token is correct
- Verify network connectivity to Last9
- Ensure `AddSource("YourActivitySourceName")` matches your ActivitySource name

**Package errors?**
- Make sure you're using .NET 6.0 or later
- Run `dotnet restore` to refresh packages

## 📚 More Info

- [OpenTelemetry .NET Docs](https://opentelemetry.io/docs/instrumentation/net/)
- [Last9 Documentation](https://docs.last9.io/)

---

**Need help?** Check your Last9 dashboard or contact support.