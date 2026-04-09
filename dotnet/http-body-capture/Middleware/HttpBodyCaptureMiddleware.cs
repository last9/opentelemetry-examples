using System.Diagnostics;
using HttpBodyCapture.Configuration;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace HttpBodyCapture.Middleware;

public class HttpBodyCaptureMiddleware
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

        // Read request body
        string? requestBody = null;
        if (_options.CaptureRequestBody && IsAllowedContentType(context.Request.ContentType))
        {
            requestBody = await ReadStreamAsync(context.Request.Body);
            context.Request.Body.Position = 0;
        }

        // Wrap response stream to capture response body
        var originalResponseBody = context.Response.Body;
        using var responseBuffer = new MemoryStream();
        context.Response.Body = responseBuffer;

        try
        {
            await _next(context);
        }
        finally
        {
            // Read response body
            string? responseBody = null;
            if (_options.CaptureResponseBody && IsAllowedContentType(context.Response.ContentType))
            {
                responseBuffer.Position = 0;
                responseBody = await ReadStreamAsync(responseBuffer);
            }

            // Add bodies as span attributes on the current Activity (created by auto-instrumentation)
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

            // Copy buffered response back to the original stream
            responseBuffer.Position = 0;
            await responseBuffer.CopyToAsync(originalResponseBody);
            context.Response.Body = originalResponseBody;
        }
    }

    private bool ShouldCapture(PathString path)
    {
        var pathValue = path.Value ?? "";

        foreach (var exclude in _options.ExcludePaths)
        {
            if (pathValue.StartsWith(exclude, StringComparison.OrdinalIgnoreCase))
                return false;
        }

        if (_options.IncludePaths.Count == 0)
            return true;

        foreach (var include in _options.IncludePaths)
        {
            if (pathValue.StartsWith(include, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }

    private bool IsAllowedContentType(string? contentType)
    {
        if (string.IsNullOrEmpty(contentType))
            return false;

        if (_options.ContentTypes.Count == 0)
            return true;

        foreach (var allowed in _options.ContentTypes)
        {
            if (contentType.Contains(allowed, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }

    private async Task<string?> ReadStreamAsync(Stream stream)
    {
        using var reader = new StreamReader(stream, leaveOpen: true);
        var buffer = new char[_options.MaxBodySizeBytes];
        var charsRead = await reader.ReadAsync(buffer, 0, buffer.Length);

        if (charsRead == 0)
            return null;

        var body = new string(buffer, 0, charsRead);

        if (charsRead >= _options.MaxBodySizeBytes)
            body += "...[TRUNCATED]";

        return body;
    }
}
