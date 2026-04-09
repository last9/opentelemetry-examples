using System.Buffers;
using System.Diagnostics;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
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

    public HttpBodyCaptureMiddleware(
        RequestDelegate next,
        IOptions<BodyCaptureOptions> options)
    {
        _next = next;
        _options = options.Value;
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

        if (!_options.CaptureResponseBody)
        {
            await _next(context);
            SetSpanAttributes(requestBody, null, context.Response.StatusCode);
            return;
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
            if (IsAllowedContentType(context.Response.ContentType))
            {
                responseBuffer.Position = 0;
                responseBody = await ReadStreamAsync(responseBuffer);
            }

            SetSpanAttributes(requestBody, responseBody, context.Response.StatusCode);

            responseBuffer.Position = 0;
            await responseBuffer.CopyToAsync(originalResponseBody);
            context.Response.Body = originalResponseBody;
        }
    }

    private void SetSpanAttributes(string? requestBody, string? responseBody, int statusCode)
    {
        var activity = Activity.Current;
        if (activity == null) return;

        var shouldRecord = !_options.CaptureOnErrorOnly || statusCode >= 400;
        if (!shouldRecord) return;

        if (!string.IsNullOrEmpty(requestBody))
            activity.SetTag("http.request.body", requestBody);
        if (!string.IsNullOrEmpty(responseBody))
            activity.SetTag("http.response.body", responseBody);
        activity.SetTag("http.response.status_code", statusCode);
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
        var maxChars = _options.MaxBodySizeBytes;
        var buffer = ArrayPool<char>.Shared.Rent(maxChars);
        try
        {
            using var reader = new StreamReader(stream, leaveOpen: true);
            var charsRead = await reader.ReadAsync(buffer, 0, maxChars);
            if (charsRead == 0) return null;
            var body = new string(buffer, 0, charsRead);
            if (charsRead == maxChars) body += "...[TRUNCATED]";
            return body;
        }
        finally
        {
            ArrayPool<char>.Shared.Return(buffer);
        }
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
        services.AddSingleton<IStartupFilter, BodyCaptureStartupFilter>();
        return services;
    }
}
