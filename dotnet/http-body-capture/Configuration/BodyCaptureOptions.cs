namespace HttpBodyCapture.Configuration;

public class BodyCaptureOptions
{
    /// <summary>Master switch to enable/disable body capture.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>Capture incoming request bodies.</summary>
    public bool CaptureRequestBody { get; set; } = true;

    /// <summary>Capture outgoing response bodies.</summary>
    public bool CaptureResponseBody { get; set; } = true;

    /// <summary>Maximum body size to capture in bytes. Bodies exceeding this are truncated.</summary>
    public int MaxBodySizeBytes { get; set; } = 8192;

    /// <summary>Only capture bodies when the response status code is 400+.</summary>
    public bool CaptureOnErrorOnly { get; set; }

    /// <summary>Content types to capture. Empty list means capture all.</summary>
    public List<string> ContentTypes { get; set; } = new()
    {
        "application/json",
        "application/xml",
        "text/plain"
    };

    /// <summary>Only capture bodies for requests matching these path prefixes. Empty list means all paths.</summary>
    public List<string> IncludePaths { get; set; } = new();

    /// <summary>Skip body capture for requests matching these path prefixes.</summary>
    public List<string> ExcludePaths { get; set; } = new()
    {
        "/health",
        "/ready",
        "/metrics"
    };
}
