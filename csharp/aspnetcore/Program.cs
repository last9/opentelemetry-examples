using System.Diagnostics;
using System.Diagnostics.Metrics;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);

// ── Configuration from environment variables ──────────────────────────────
var serviceName    = Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME")            ?? "last9-csharp-example";
var serviceVersion = typeof(Program).Assembly.GetName().Version?.ToString()             ?? "1.0.0";
var otlpEndpoint   = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT")  ?? "https://otlp.last9.io";
var otlpHeaders    = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS")   ?? "";
var environment    = Environment.GetEnvironmentVariable("DEPLOYMENT_ENVIRONMENT")        ?? "production";

otlpEndpoint = otlpEndpoint.TrimEnd('/');

// ── Shared resource ───────────────────────────────────────────────────────
var resourceBuilder = ResourceBuilder.CreateDefault()
    .AddService(serviceName: serviceName, serviceVersion: serviceVersion)
    .AddAttributes(new Dictionary<string, object>
    {
        ["deployment.environment"] = environment,
    });

// ── OpenTelemetry — Traces + Metrics ─────────────────────────────────────
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r
        .AddService(serviceName: serviceName, serviceVersion: serviceVersion)
        .AddAttributes(new Dictionary<string, object>
        {
            ["deployment.environment"] = environment,
        }))
    .WithTracing(b =>
    {
        b.AddAspNetCoreInstrumentation(o =>
         {
             o.RecordException = true;
             o.Filter = ctx => ctx.Request.Path != "/health";
         })
         .AddHttpClientInstrumentation(o => { o.RecordException = true; })
         .AddSource(Telemetry.Source.Name)
         .AddOtlpExporter(o =>
         {
             o.Endpoint = new Uri($"{otlpEndpoint}/v1/traces");
             o.Headers  = otlpHeaders;
             o.Protocol = OtlpExportProtocol.HttpProtobuf;
         });
    })
    .WithMetrics(b =>
    {
        b.AddAspNetCoreInstrumentation()   // HTTP server metrics (request count, duration)
         .AddHttpClientInstrumentation()   // HTTP client metrics
         .AddRuntimeInstrumentation()      // .NET runtime: GC, thread pool, heap
         .AddMeter(Telemetry.Meter.Name)   // custom application metrics
         .AddOtlpExporter(o =>
         {
             o.Endpoint = new Uri($"{otlpEndpoint}/v1/metrics");
             o.Headers  = otlpHeaders;
             o.Protocol = OtlpExportProtocol.HttpProtobuf;
         });
    });

// ── OpenTelemetry — Logs ──────────────────────────────────────────────────
builder.Logging.AddOpenTelemetry(options =>
{
    options.SetResourceBuilder(resourceBuilder);
    options.AddOtlpExporter(o =>
    {
        o.Endpoint = new Uri($"{otlpEndpoint}/v1/logs");
        o.Headers  = otlpHeaders;
        o.Protocol = OtlpExportProtocol.HttpProtobuf;
    });
    options.IncludeFormattedMessage = true;
    options.IncludeScopes           = true;
});

// ── App ───────────────────────────────────────────────────────────────────
var app = builder.Build();

// ForceFlush on graceful shutdown — prevents span/metric loss when process exits
app.Lifetime.ApplicationStopping.Register(() =>
{
    app.Logger.LogInformation("Flushing OpenTelemetry data before shutdown...");
    app.Services.GetRequiredService<TracerProvider>().ForceFlush(5000);
    app.Services.GetRequiredService<MeterProvider>().ForceFlush(5000);
});

// ── Routes ────────────────────────────────────────────────────────────────
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/", () => new
{
    service   = serviceName,
    version   = serviceVersion,
    endpoints = new[] { "GET /orders", "GET /orders/{id}", "POST /orders" },
});

app.MapGet("/orders", (ILogger<Program> logger) =>
{
    using var activity = Telemetry.Source.StartActivity("list-orders");

    logger.LogInformation("Listing all orders");

    var orders = FakeStore.GetAll();

    activity?.SetTag("orders.count", orders.Count);
    Telemetry.OrdersListed.Add(1);

    return Results.Ok(orders);
});

app.MapGet("/orders/{id:int}", (int id, ILogger<Program> logger) =>
{
    using var activity = Telemetry.Source.StartActivity("get-order");
    activity?.SetTag("order.id", id);

    logger.LogInformation("Fetching order {OrderId}", id);

    var order = FakeStore.GetById(id);
    if (order is null)
    {
        activity?.SetStatus(ActivityStatusCode.Error, "Order not found");
        logger.LogWarning("Order {OrderId} not found", id);
        return Results.NotFound(new { error = $"Order {id} not found" });
    }

    return Results.Ok(order);
});

app.MapPost("/orders", (CreateOrderRequest req, ILogger<Program> logger) =>
{
    using var activity = Telemetry.Source.StartActivity("create-order");

    logger.LogInformation("Creating order for product {Product}", req.Product);

    if (string.IsNullOrWhiteSpace(req.Product))
    {
        activity?.SetStatus(ActivityStatusCode.Error, "Product name required");
        return Results.BadRequest(new { error = "Product name is required" });
    }

    var order = FakeStore.Create(req.Product, req.Amount);
    activity?.SetTag("order.id",     order.Id);
    activity?.SetTag("order.amount", order.Amount);

    Telemetry.OrdersCreated.Add(1, new KeyValuePair<string, object?>("product", req.Product));
    logger.LogInformation("Order {OrderId} created for {Product} at ${Amount}", order.Id, order.Product, order.Amount);

    return Results.Created($"/orders/{order.Id}", order);
});

app.Run();

// ── Models ────────────────────────────────────────────────────────────────
record Order(int Id, string Product, double Amount, DateTime CreatedAt);
record CreateOrderRequest(string Product, double Amount);

// ── In-memory store ───────────────────────────────────────────────────────
static class FakeStore
{
    private static readonly List<Order> _orders =
    [
        new(1, "Widget",    99.99,  DateTime.UtcNow.AddDays(-2)),
        new(2, "Gadget",   149.99,  DateTime.UtcNow.AddDays(-1)),
        new(3, "Doohickey", 49.99,  DateTime.UtcNow),
    ];
    private static int _nextId = 4;

    public static List<Order> GetAll()        => _orders;
    public static Order?      GetById(int id) => _orders.FirstOrDefault(o => o.Id == id);
    public static Order       Create(string product, double amount)
    {
        var order = new Order(_nextId++, product, amount, DateTime.UtcNow);
        _orders.Add(order);
        return order;
    }
}

// ── Telemetry — ActivitySource + Meter ───────────────────────────────────
static class Telemetry
{
    public static readonly ActivitySource Source = new("last9-csharp-example", "1.0.0");

    public static readonly Meter Meter = new("last9-csharp-example", "1.0.0");

    // Custom counters
    public static readonly Counter<long> OrdersCreated = Meter.CreateCounter<long>(
        "orders.created", description: "Total orders created");

    public static readonly Counter<long> OrdersListed = Meter.CreateCounter<long>(
        "orders.listed", description: "Total order list requests");
}
