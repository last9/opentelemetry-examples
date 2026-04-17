using AspNetCore.Data;

// ── No OTel SDK packages or configuration needed ──────────────────────────────
// Traces, metrics, and db spans are captured by the OTel CLR profiler injected
// at the IIS / Kestrel process level via environment variables.
// See setup-otel.ps1 (IIS) or env.example (Kestrel) for setup instructions.
// ─────────────────────────────────────────────────────────────────────────────

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddHttpClient();
builder.Services.AddSingleton<TodoRepository>();
builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

app.MapControllers();

// ── Minimal API endpoints ─────────────────────────────────────────────────────
// These are instrumented alongside the controller endpoints — same profiler,
// same trace context. Both styles work with zero OTel code.

app.MapGet("/", () => Results.Ok(new { service = "aspnet-core-otel-demo", status = "ok" }));

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

// GET /minimal/todos — minimal API equivalent of TodosController.GetAll
app.MapGet("/minimal/todos", async (TodoRepository repo) =>
    Results.Ok(await repo.GetAllAsync()));

// POST /minimal/todos
app.MapPost("/minimal/todos", async (AspNetCore.Models.Todo todo, TodoRepository repo) =>
{
    if (string.IsNullOrWhiteSpace(todo.Title))
        return Results.BadRequest(new { error = "Title is required" });
    var created = await repo.CreateAsync(todo);
    return Results.Created($"/minimal/todos/{created.Id}", created);
});

// GET /minimal/upstream — outbound HTTP call auto-instrumented via IHttpClientFactory
app.MapGet("/minimal/upstream", async (IHttpClientFactory factory) =>
{
    var client = factory.CreateClient();
    var response = await client.GetAsync("https://httpbin.org/json");
    var body = await response.Content.ReadAsStringAsync();
    return Results.Ok(new
    {
        status  = (int)response.StatusCode,
        preview = body[..Math.Min(200, body.Length)]
    });
});

app.Run();
