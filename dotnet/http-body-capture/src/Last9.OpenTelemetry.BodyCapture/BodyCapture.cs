using System.Diagnostics;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Last9.OpenTelemetry;

public class BodyCaptureOptions
{
    public bool Enabled { get; set; } = true;
    public bool CaptureRequestBody { get; set; } = true;
    public bool CaptureResponseBody { get; set; } = true;
    public int MaxBodySizeBytes { get; set; } = 8192;
    public bool CaptureOnErrorOnly { get; set; }
    public List<string> ContentTypes { get; set; } = new() { "application/json", "application/xml", "text/plain" };
    public List<string> IncludePaths { get; set; } = new();
    public List<string> ExcludePaths { get; set; } = new() { "/health", "/ready", "/metrics" };
}

internal class HttpBodyCaptureMiddleware
{
    private readonly RequestDelegate _next;
    private readonly BodyCaptureOptions _options;
    private readonly ILogger<HttpBodyCaptureMiddleware> _logger;

    public HttpBodyCaptureMiddleware(
        RequestDelegate next,
        IOptions<BodyCaptureOptions> options,
        ILogger<HttpBodyCaptureMiddleware> logger)
    {
        _next = next;
        _options = options.Value;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!_options.Enabled || !ShouldCapture(context.Request.Path))
        {
            await _next(context);
            return;
        }

        context.Request.EnableBuffering();

        string? requestBody = null;
        if (_options.CaptureRequestBody && IsAllowedContentType(context.Request.ContentType))
        {
            requestBody = await ReadStreamAsync(context.Request.Body);
            context.Request.Body.Position = 0;
        }

        var originalResponseBody = context.Response.Body;
        using var responseBuffer = new MemoryStream();
        context.Response.Body = responseBuffer;

        try
        {
            await _next(context);
        }
        finally
        {
            string? responseBody = null;
            if (_options.CaptureResponseBody && IsAllowedContentType(context.Response.ContentType))
            {
                responseBuffer.Position = 0;
                responseBody = await ReadStreamAsync(responseBuffer);
            }

            var activity = Activity.Current;
            if (activity != null)
            {
                var shouldRecord = !_options.CaptureOnErrorOnly || context.Response.StatusCode >= 400;
                if (shouldRecord)
                {
                    if (!string.IsNullOrEmpty(requestBody))
                        activity.SetTag("http.request.body", requestBody);
                    if (!string.IsNullOrEmpty(responseBody))
                        activity.SetTag("http.response.body", responseBody);
                    activity.SetTag("http.response.status_code", context.Response.StatusCode);
                }
            }

            responseBuffer.Position = 0;
            await responseBuffer.CopyToAsync(originalResponseBody);
            context.Response.Body = originalResponseBody;
        }
    }

    private bool ShouldCapture(PathString path)
    {
        var pathValue = path.Value ?? "";
        foreach (var exclude in _options.ExcludePaths)
            if (pathValue.StartsWith(exclude, StringComparison.OrdinalIgnoreCase))
                return false;
        if (_options.IncludePaths.Count == 0)
            return true;
        foreach (var include in _options.IncludePaths)
            if (pathValue.StartsWith(include, StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    private bool IsAllowedContentType(string? contentType)
    {
        if (string.IsNullOrEmpty(contentType)) return false;
        if (_options.ContentTypes.Count == 0) return true;
        foreach (var allowed in _options.ContentTypes)
            if (contentType.Contains(allowed, StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    private async Task<string?> ReadStreamAsync(Stream stream)
    {
        using var reader = new StreamReader(stream, leaveOpen: true);
        var buffer = new char[_options.MaxBodySizeBytes];
        var charsRead = await reader.ReadAsync(buffer, 0, buffer.Length);
        if (charsRead == 0) return null;
        var body = new string(buffer, 0, charsRead);
        if (charsRead >= _options.MaxBodySizeBytes) body += "...[TRUNCATED]";
        return body;
    }
}

internal class BodyCaptureStartupFilter : IStartupFilter
{
    public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next)
    {
        return builder =>
        {
            builder.UseMiddleware<HttpBodyCaptureMiddleware>();
            next(builder);
        };
    }
}

public static class BodyCaptureServiceCollectionExtensions
{
    public static IServiceCollection AddHttpBodyCapture(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.Configure<BodyCaptureOptions>(configuration.GetSection("BodyCapture"));
        services.AddTransient<IStartupFilter, BodyCaptureStartupFilter>();
        return services;
    }
}
