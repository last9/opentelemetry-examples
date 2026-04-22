import { LoggerService } from "@nestjs/common";
import { SeverityNumber, logs } from "@opentelemetry/api-logs";
import { context } from "@opentelemetry/api";

// NestJS logger that emits structured records via OTel Logs API.
// Records are exported to Last9 via OTLP alongside traces.
// trace_id and span_id are set automatically from the active span context,
// enabling log-to-trace correlation in the Last9 UI.
export class OtelLogger implements LoggerService {
  private readonly otelLogger = logs.getLogger("nestjs-sqs");

  log(message: unknown, context?: string) {
    this.emit(SeverityNumber.INFO, "INFO", message, context);
  }

  error(message: unknown, trace?: string, ctx?: string) {
    this.emit(SeverityNumber.ERROR, "ERROR", message, ctx, trace);
  }

  warn(message: unknown, context?: string) {
    this.emit(SeverityNumber.WARN, "WARN", message, context);
  }

  debug(message: unknown, context?: string) {
    this.emit(SeverityNumber.DEBUG, "DEBUG", message, context);
  }

  verbose(message: unknown, context?: string) {
    this.emit(SeverityNumber.TRACE, "TRACE", message, context);
  }

  private emit(
    severityNumber: SeverityNumber,
    severityText: string,
    message: unknown,
    logContext?: string,
    stackTrace?: string,
  ) {
    const attributes: Record<string, string> = {};

    if (logContext) attributes["code.namespace"] = logContext;
    if (stackTrace) attributes["exception.stacktrace"] = stackTrace;

    // Flatten structured log objects into attributes for queryability in Last9
    if (typeof message === "object" && message !== null) {
      for (const [k, v] of Object.entries(message)) {
        if (typeof v === "string" || typeof v === "number") {
          attributes[k] = String(v);
        }
      }
    }

    this.otelLogger.emit({
      severityNumber,
      severityText,
      body:
        typeof message === "string" ? message : JSON.stringify(message),
      attributes,
      // OTel SDK automatically attaches trace_id + span_id from active context.
      // No manual injection needed here — the SDK reads context.active().
      context: context.active(),
    });
  }
}
