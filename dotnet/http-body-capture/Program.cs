using HttpBodyCapture.Configuration;
using HttpBodyCapture.Middleware;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateBuilder(args);

// Configure body capture options from appsettings.json
builder.Services.Configure<BodyCaptureOptions>(
    builder.Configuration.GetSection("BodyCapture"));

var app = builder.Build();

// Register body capture middleware — enriches auto-instrumented spans with request/response bodies
app.UseMiddleware<HttpBodyCaptureMiddleware>();

// Sample patient API with PHI data (for testing PII redaction)
app.MapGet("/api/patients/{id}", (string id) =>
{
    return Results.Json(new
    {
        id,
        name = "Jane Doe",
        dateOfBirth = "1985-03-15",
        ssn = "123-45-6789",
        email = "jane.doe@example.com",
        phone = "555-123-4567",
        insuranceId = "INS-789456123",
        address = new
        {
            street = "123 Main St",
            city = "Springfield",
            state = "IL",
            zip = "62704-1234"
        },
        diagnosis = "Routine checkup",
        mrn = "MRN-2024-00456"
    });
});

app.MapPost("/api/patients", async ([FromBody] object patient) =>
{
    return Results.Json(new
    {
        status = "created",
        message = "Patient record created",
        timestamp = DateTime.UtcNow
    });
});

app.MapGet("/api/orders/{id}", (string id) =>
{
    return Results.Json(new
    {
        orderId = id,
        medication = "Amoxicillin 500mg",
        quantity = 30,
        prescribedBy = "Dr. Smith",
        patientSsn = "987-65-4321",
        patientEmail = "patient@hospital.example.com"
    });
});

app.MapGet("/health", () => Results.Ok("healthy"));

app.Run();
