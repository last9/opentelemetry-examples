import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import {
  DeleteMessageCommand,
  Message,
  ReceiveMessageCommand,
  SQSClient,
} from "@aws-sdk/client-sqs";
import {
  SpanContext,
  SpanKind,
  SpanStatusCode,
  context,
  propagation,
  trace,
} from "@opentelemetry/api";
import { MessageProcessorService } from "../processing/message-processor.service";

@Injectable()
export class SqsPollerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SqsPollerService.name);
  private readonly tracer = trace.getTracer("sqs-poller");
  private readonly sqs: SQSClient;
  private pollingTimer: ReturnType<typeof setTimeout> | null = null;
  private running = false;

  constructor(private readonly processor: MessageProcessorService) {
    this.sqs = new SQSClient({
      region: process.env.AWS_REGION ?? "us-east-1",
      ...(process.env.SQS_ENDPOINT
        ? { endpoint: process.env.SQS_ENDPOINT }
        : {}),
    });
  }

  onModuleInit() {
    this.running = true;
    void this.schedulePoll();
  }

  onModuleDestroy() {
    this.running = false;
    if (this.pollingTimer) clearTimeout(this.pollingTimer);
  }

  // Uses setTimeout-chaining instead of setInterval so polls never overlap.
  private schedulePoll() {
    const intervalMs = parseInt(process.env.POLL_INTERVAL_MS ?? "5000", 10);
    this.pollingTimer = setTimeout(async () => {
      if (!this.running) return;
      await this.pollOnce();
      if (this.running) this.schedulePoll();
    }, intervalMs);
  }

  private async pollOnce() {
    // Root span for the entire polling cycle — groups all message processing
    // for this interval tick under one traceable unit.
    const pollSpan = this.tracer.startSpan("sqs.poll_cycle", {
      kind: SpanKind.INTERNAL,
      attributes: {
        "messaging.system": "aws.sqs",
        "messaging.destination.name": process.env.SQS_QUEUE_NAME,
      },
    });

    await context.with(trace.setSpan(context.active(), pollSpan), async () => {
      try {
        // AwsInstrumentation auto-instruments this call and creates a
        // SPAN_KIND_CONSUMER span named "<queue> receive" as a child.
        const messages = await this.receiveMessages();

        pollSpan.setAttribute("messaging.batch.message_count", messages.length);

        this.logger.log({
          message: "poll_cycle",
          count: messages.length,
          ...this.getTraceContext(),
        });

        if (messages.length > 0) {
          // Process all messages concurrently, each in its own child span.
          await Promise.all(messages.map((msg) => this.processMessage(msg)));
        }

        pollSpan.setStatus({ code: SpanStatusCode.OK });
      } catch (err) {
        pollSpan.recordException(err as Error);
        pollSpan.setStatus({
          code: SpanStatusCode.ERROR,
          message: String(err),
        });
        this.logger.error({
          message: "poll_cycle_error",
          error: String(err),
          ...this.getTraceContext(),
        });
      } finally {
        pollSpan.end();
      }
    });
  }

  private async receiveMessages(): Promise<Message[]> {
    const response = await this.sqs.send(
      new ReceiveMessageCommand({
        QueueUrl: process.env.SQS_QUEUE_URL,
        MaxNumberOfMessages: 10,
        WaitTimeSeconds: parseInt(process.env.SQS_WAIT_TIME_SECONDS ?? "5", 10),
        // 'All' is required for AwsInstrumentation to read the traceparent
        // MessageAttribute injected by the producer.
        MessageAttributeNames: ["All"],
      }),
    );
    return response.Messages ?? [];
  }

  private async processMessage(message: Message) {
    // Extract the producer's span context from MessageAttributes.
    // AwsInstrumentation injects 'traceparent' on the send side automatically.
    const producerSpanCtx = this.extractProducerContext(message);

    // Per-message span: child of poll_cycle in this service's trace,
    // linked to the producer's trace for cross-trace navigation.
    //
    // Using links (not parent) keeps consumer trace independent —
    // each subscriber creates its own trace tree while still referencing origin.
    const msgSpan = this.tracer.startSpan(
      `${process.env.SQS_QUEUE_NAME ?? "queue"} process`,
      {
        kind: SpanKind.CONSUMER,
        links: producerSpanCtx ? [{ context: producerSpanCtx }] : [],
        attributes: {
          "messaging.system": "aws.sqs",
          "messaging.destination.name": process.env.SQS_QUEUE_NAME,
          "messaging.message.id": message.MessageId,
          "messaging.operation": "process",
        },
      },
    );

    await context.with(trace.setSpan(context.active(), msgSpan), async () => {
      try {
        this.logger.log({
          message: "message_processing_start",
          messageId: message.MessageId,
          // trace_id + span_id appear in every log line — queryable in Last9
          ...this.getTraceContext(),
        });

        await this.processor.handle(message);

        // AwsInstrumentation auto-instruments DeleteMessage as a child span.
        await this.deleteMessage(message);

        msgSpan.setStatus({ code: SpanStatusCode.OK });

        this.logger.log({
          message: "message_processing_done",
          messageId: message.MessageId,
          ...this.getTraceContext(),
        });
      } catch (err) {
        msgSpan.recordException(err as Error);
        msgSpan.setStatus({
          code: SpanStatusCode.ERROR,
          message: String(err),
        });
        this.logger.error({
          message: "message_processing_failed",
          messageId: message.MessageId,
          error: String(err),
          ...this.getTraceContext(),
        });
      } finally {
        msgSpan.end();
      }
    });
  }

  private extractProducerContext(message: Message): SpanContext | null {
    if (!message.MessageAttributes) return null;

    // Build a carrier from MessageAttributes for W3C propagation extraction.
    // AwsInstrumentation on the producer injects 'traceparent' here automatically.
    const carrier: Record<string, string> = {};
    for (const [key, attr] of Object.entries(message.MessageAttributes)) {
      const val = attr as { StringValue?: string };
      if (val.StringValue) carrier[key.toLowerCase()] = val.StringValue;
    }

    const extractedCtx = propagation.extract(context.active(), carrier);
    const spanCtx = trace.getSpanContext(extractedCtx);
    return spanCtx ?? null;
  }

  private async deleteMessage(message: Message) {
    await this.sqs.send(
      new DeleteMessageCommand({
        QueueUrl: process.env.SQS_QUEUE_URL,
        ReceiptHandle: message.ReceiptHandle!,
      }),
    );
  }

  private getTraceContext(): Record<string, string> {
    const span = trace.getActiveSpan();
    if (!span) return {};
    const ctx = span.spanContext();
    return { trace_id: ctx.traceId, span_id: ctx.spanId };
  }
}
