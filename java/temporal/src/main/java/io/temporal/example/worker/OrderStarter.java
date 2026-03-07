package io.temporal.example.worker;

import io.opentracing.Tracer;
import io.opentracing.tag.Tags;
import io.temporal.client.WorkflowClient;
import io.temporal.client.WorkflowClientOptions;
import io.temporal.client.WorkflowOptions;
import io.temporal.example.workflow.OrderWorkflow;
import io.temporal.opentracing.OpenTracingClientInterceptor;
import io.temporal.opentracing.OpenTracingOptions;
import io.temporal.opentracing.SpanOperationType;
import io.temporal.serviceclient.WorkflowServiceStubs;
import io.temporal.serviceclient.WorkflowServiceStubsOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.UUID;

public class OrderStarter {

    private static final Logger logger = LoggerFactory.getLogger(OrderStarter.class);

    public static void main(String[] args) {
        // Initialize OpenTelemetry tracing
        TracingConfig.initializeTracing();

        // Get Temporal server address from environment
        String temporalAddress = System.getenv().getOrDefault("TEMPORAL_ADDRESS", "localhost:7233");
        logger.info("Connecting to Temporal server at: {}", temporalAddress);

        // Create workflow service stubs
        WorkflowServiceStubs service = WorkflowServiceStubs.newServiceStubs(
                WorkflowServiceStubsOptions.newBuilder()
                        .setTarget(temporalAddress)
                        .build()
        );

        // Configure OpenTracing options with proper span kinds
        OpenTracingOptions tracingOptions = OpenTracingOptions.newBuilder()
                .setSpanBuilderProvider((tracer, context) -> {
                    String spanName = context.getActionName();
                    Tracer.SpanBuilder builder = tracer.buildSpan(spanName);

                    // Set span kind based on operation type
                    SpanOperationType opType = context.getSpanOperationType();
                    switch (opType) {
                        // SERVER spans - receiving/handling work
                        case RUN_WORKFLOW:
                        case RUN_ACTIVITY:
                        case HANDLE_QUERY:
                        case HANDLE_SIGNAL:
                        case HANDLE_UPDATE:
                            builder.withTag(Tags.SPAN_KIND.getKey(), Tags.SPAN_KIND_SERVER);
                            break;
                        // CLIENT spans - initiating work
                        case START_WORKFLOW:
                        case SIGNAL_WITH_START_WORKFLOW:
                        case START_CHILD_WORKFLOW:
                        case START_CONTINUE_AS_NEW_WORKFLOW:
                        case START_ACTIVITY:
                        case SIGNAL_EXTERNAL_WORKFLOW:
                        case QUERY_WORKFLOW:
                        case SIGNAL_WORKFLOW:
                        case UPDATE_WORKFLOW:
                        default:
                            builder.withTag(Tags.SPAN_KIND.getKey(), Tags.SPAN_KIND_CLIENT);
                            break;
                    }

                    // Add workflow context as tags
                    if (context.getWorkflowId() != null) {
                        builder.withTag("temporal.workflow.id", context.getWorkflowId());
                    }
                    if (context.getRunId() != null) {
                        builder.withTag("temporal.run.id", context.getRunId());
                    }
                    builder.withTag("temporal.operation", opType.name());

                    return builder;
                })
                .build();

        // Create workflow client with OpenTracing interceptor
        WorkflowClient client = WorkflowClient.newInstance(
                service,
                WorkflowClientOptions.newBuilder()
                        .setInterceptors(new OpenTracingClientInterceptor(tracingOptions))
                        .build()
        );

        // Generate test data
        String orderId = "ORD-" + UUID.randomUUID().toString().substring(0, 8);
        String customerId = "CUST-001";
        double amount = 99.99;

        // Create workflow stub
        OrderWorkflow workflow = client.newWorkflowStub(
                OrderWorkflow.class,
                WorkflowOptions.newBuilder()
                        .setTaskQueue(OrderWorker.TASK_QUEUE)
                        .setWorkflowId("order-" + orderId)
                        .build()
        );

        // Start workflow and wait for result
        logger.info("Starting order workflow: orderId={}, customerId={}, amount={}", orderId, customerId, amount);
        String result = workflow.processOrder(orderId, customerId, amount);
        logger.info("Workflow completed: result={}", result);

        System.exit(0);
    }
}
