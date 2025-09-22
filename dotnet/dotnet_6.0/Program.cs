using System.Diagnostics;
using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Resources;

class Program
{
    private static readonly ActivitySource ActivitySource = new("OtelTestApp");

    static void Main(string[] args)
    {
        // Get configuration from environment variables
        var serviceName = Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME") ?? "OtelTestApp";
        var tracesExporter = Environment.GetEnvironmentVariable("OTEL_TRACES_EXPORTER") ?? "console";
        var otlpEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT");
        var otlpHeaders = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS");
        var resourceAttributes = Environment.GetEnvironmentVariable("OTEL_RESOURCE_ATTRIBUTES");

        Console.WriteLine($"=== OpenTelemetry .NET 6.0 Test Application ===");
        Console.WriteLine($"Service Name: {serviceName}");
        Console.WriteLine($"Traces Exporter: {tracesExporter}");
        if (!string.IsNullOrEmpty(otlpEndpoint))
        {
            Console.WriteLine($"OTLP Endpoint: {otlpEndpoint}");
        }
        Console.WriteLine();

        // Build resource attributes
        var resourceBuilder = ResourceBuilder.CreateDefault()
            .AddService(serviceName: serviceName, serviceVersion: "1.0.0");

        // Add custom resource attributes if provided
        if (!string.IsNullOrEmpty(resourceAttributes))
        {
            var attributes = resourceAttributes.Split(',');
            foreach (var attribute in attributes)
            {
                var parts = attribute.Split('=');
                if (parts.Length == 2)
                {
                    resourceBuilder.AddAttributes(new Dictionary<string, object> { { parts[0].Trim(), parts[1].Trim() } });
                }
            }
        }

        // Configure OpenTelemetry
        var tracerProviderBuilder = Sdk.CreateTracerProviderBuilder()
            .SetResourceBuilder(resourceBuilder)
            .AddSource("OtelTestApp");

        // Add exporters based on configuration
        if (tracesExporter.Contains("console") || string.IsNullOrEmpty(otlpEndpoint))
        {
            tracerProviderBuilder.AddConsoleExporter();
            Console.WriteLine("Console exporter enabled");
        }

        if (tracesExporter.Contains("otlp") && !string.IsNullOrEmpty(otlpEndpoint))
        {
            var otlpBuilder = tracerProviderBuilder.AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri(otlpEndpoint);
                if (!string.IsNullOrEmpty(otlpHeaders))
                {
                    // Parse headers like "Authorization=Basic YOUR_TOKEN_HERE"
                    var headers = otlpHeaders.Split(',');
                    foreach (var header in headers)
                    {
                        var parts = header.Split('=');
                        if (parts.Length == 2)
                        {
                            options.Headers = parts[0].Trim() + "=" + parts[1].Trim();
                        }
                    }
                }
            });
            Console.WriteLine("OTLP exporter enabled");
        }

        using var tracerProvider = tracerProviderBuilder.Build();

        Console.WriteLine("Starting application with tracing enabled...\n");

        // Create a main activity
        using (var mainActivity = ActivitySource.StartActivity("Main"))
        {
            mainActivity?.SetTag("app.name", serviceName);
            mainActivity?.SetTag("app.version", "1.0.0");
            
            Console.WriteLine("Hello, World!");
            
            // Simulate some work with nested activities
            SimulateWork();
            
            Console.WriteLine("\nApplication completed successfully!");
        }
    }

    static void SimulateWork()
    {
        using (var workActivity = ActivitySource.StartActivity("SimulateWork"))
        {
            workActivity?.SetTag("work.type", "simulation");
            workActivity?.SetTag("work.duration", "short");
            
            Console.WriteLine("Doing some simulated work...");
            
            // Simulate processing time
            System.Threading.Thread.Sleep(100);
            
            // Add some child work
            ProcessData();
            
            Console.WriteLine("Work completed!");
        }
    }

    static void ProcessData()
    {
        using (var processActivity = ActivitySource.StartActivity("ProcessData"))
        {
            processActivity?.SetTag("process.type", "data");
            processActivity?.SetTag("process.items", 5);
            
            Console.WriteLine("Processing data...");
            
            // Simulate data processing
            for (int i = 1; i <= 5; i++)
            {
                using (var itemActivity = ActivitySource.StartActivity($"ProcessItem-{i}"))
                {
                    itemActivity?.SetTag("item.id", i);
                    itemActivity?.SetTag("item.status", "processed");
                    
                    Console.WriteLine($"  Processing item {i}");
                    System.Threading.Thread.Sleep(50);
                }
            }
            
            Console.WriteLine("Data processing completed!");
        }
    }
}
