import { context, trace, SpanKind } from "@opentelemetry/api";
import { SEMATTRS_HTTP_METHOD, SEMATTRS_HTTP_ROUTE, SEMATTRS_HTTP_TARGET, SEMATTRS_HTTP_USER_AGENT, SEMATTRS_HTTP_HOST, SEMATTRS_HTTP_SCHEME, SEMATTRS_HTTP_STATUS_CODE, SEMATTRS_HTTP_CLIENT_IP } from "@opentelemetry/semantic-conventions";

function normalizePath(path) {
  // Replace UUIDs
  path = path.replace(
    /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g,
    ":uuid",
  );

  // Replace numeric IDs
  path = path.replace(/\/\d+(?=\/|$)/g, "/:id");

  // Replace date patterns (YYYY-MM-DD)
  path = path.replace(/\/\d{4}-\d{2}-\d{2}(?=\/|$)/g, "/:date");

  // Replace timestamps (Unix epoch)
  path = path.replace(/\/\d{10,13}(?=\/|$)/g, "/:timestamp");

  // Replace GUIDs (without dashes)
  path = path.replace(/\/[0-9a-fA-F]{32}(?=\/|$)/g, "/:guid");

  // Replace language codes (e.g., en-US, fr, de-DE)
  path = path.replace(/\/[a-z]{2}(-[A-Z]{2})?(?=\/|$)/g, "/:lang");

  return path;
}

export function otelMiddleware() {
  return async (c, next) => {
    const { req } = c;
    const tracer = trace.getTracer("hono-app"); // Replace with your service name

    const normalizedPath = normalizePath(req.path);
    const span = tracer.startSpan(`${req.method} ${normalizedPath}`, {
      kind: SpanKind.SERVER,
      attributes: {
        [SEMATTRS_HTTP_METHOD]: req.method,
        [SEMATTRS_HTTP_ROUTE]: req.path,
        [SEMATTRS_HTTP_TARGET]: req.url,
        [SEMATTRS_HTTP_USER_AGENT]: req.header("user-agent"),
        [SEMATTRS_HTTP_HOST]: req.header("host"),
        [SEMATTRS_HTTP_SCHEME]: req.url.startsWith("https")
          ? "https"
          : "http",
        [SEMATTRS_HTTP_CLIENT_IP]: c.env.ip ? c.env.ip : undefined,
      },
    });

    // Set the current span on the context
    const ctx = trace.setSpan(context.active(), span);

    // Run the handler within the context
    await context.with(ctx, async () => {
      try {
        // Call the next middleware or route handler
        await next();

        // Add response attributes
        span.setAttributes({
          [SEMATTRS_HTTP_STATUS_CODE]: c.res.status,
        });
      } catch (error) {
        // Record any errors
        span.recordException(error);
        span.setStatus({ code: trace.SpanStatusCode.ERROR });
        throw error;
      } finally {
        // End the span
        span.end();
      }
    });
  };
}
