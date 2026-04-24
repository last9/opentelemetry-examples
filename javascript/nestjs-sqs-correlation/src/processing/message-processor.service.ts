import { Injectable, Logger } from "@nestjs/common";
import { Message } from "@aws-sdk/client-sqs";
import { trace } from "@opentelemetry/api";

@Injectable()
export class MessageProcessorService {
  private readonly logger = new Logger(MessageProcessorService.name);

  async handle(message: Message): Promise<void> {
    const body = message.Body ? JSON.parse(message.Body) : {};

    // Active span here is the per-message span set by SqsPollerService.
    // Logs include trace_id + span_id from that context automatically.
    this.logger.log({
      message: "handling_message",
      messageId: message.MessageId,
      eventType: body.type,
      ...getTraceContext(),
    });

    // Your business logic here.
    // Any HTTP calls, DB queries, or downstream SQS sends made here
    // will automatically be child spans of the per-message span.
    await simulateWork(body);

    this.logger.log({
      message: "message_handled",
      messageId: message.MessageId,
      ...getTraceContext(),
    });
  }
}

function getTraceContext(): Record<string, string> {
  const span = trace.getActiveSpan();
  if (!span) return {};
  const ctx = span.spanContext();
  return { trace_id: ctx.traceId, span_id: ctx.spanId };
}

async function simulateWork(_body: unknown): Promise<void> {
  await new Promise((r) => setTimeout(r, 50 + Math.random() * 100));
}
