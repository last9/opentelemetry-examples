import { Injectable } from "@nestjs/common";
import {
  MessageAttributeValue,
  SendMessageCommand,
  SQSClient,
} from "@aws-sdk/client-sqs";
import { context, propagation, trace } from "@opentelemetry/api";

@Injectable()
export class SqsProducerService {
  private readonly sqs: SQSClient;

  constructor() {
    this.sqs = new SQSClient({
      region: process.env.AWS_REGION ?? "us-east-1",
      ...(process.env.SQS_ENDPOINT
        ? { endpoint: process.env.SQS_ENDPOINT }
        : {}),
    });
  }

  async send(payload: Record<string, unknown>): Promise<void> {
    // Inject the active span's W3C traceparent into MessageAttributes so the
    // consumer (SqsPollerService) can extract and link back to this trace.
    //
    // AwsInstrumentation does this automatically when you have it registered —
    // shown here explicitly for clarity on what propagation looks like.
    const messageAttributes: Record<string, MessageAttributeValue> = {};
    propagation.inject(context.active(), messageAttributes, {
      set(carrier, key, value) {
        carrier[key] = { DataType: "String", StringValue: value };
      },
    });

    await this.sqs.send(
      new SendMessageCommand({
        QueueUrl: process.env.SQS_QUEUE_URL,
        MessageBody: JSON.stringify(payload),
        MessageAttributes: messageAttributes,
      }),
    );
  }
}

export function getTraceContext(): Record<string, string> {
  const span = trace.getActiveSpan();
  if (!span) return {};
  const ctx = span.spanContext();
  return { trace_id: ctx.traceId, span_id: ctx.spanId };
}
