package io.temporal.otel.advice;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import net.bytebuddy.asm.Advice;

/**
 * ByteBuddy advice for WorkflowClient.start() - creates CLIENT spans.
 */
@SuppressWarnings("unused")
public class WorkflowStartAdvice {

    private static final Tracer tracer = GlobalOpenTelemetry.getTracer("io.temporal");

    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static void onEnter(
            @Advice.This Object self,
            @Advice.Argument(0) Object functions,
            @Advice.Local("otelSpan") Span span,
            @Advice.Local("otelScope") Scope scope) {

        // Extract workflow info from the invoker if possible
        String workflowType = "UnknownWorkflow";
        String workflowId = "unknown";

        try {
            // Try to get workflow type from the function name
            if (functions != null) {
                workflowType = functions.getClass().getSimpleName();
            }
        } catch (Exception ignored) {
        }

        span = tracer.spanBuilder("StartWorkflow:" + workflowType)
            .setSpanKind(SpanKind.CLIENT)
            .setAttribute("temporal.workflow.type", workflowType)
            .setAttribute("temporal.operation", "START_WORKFLOW")
            .setAttribute("rpc.system", "temporal")
            .setAttribute("rpc.service", "WorkflowService")
            .setAttribute("rpc.method", "StartWorkflowExecution")
            .startSpan();

        scope = span.makeCurrent();
    }

    @Advice.OnMethodExit(suppress = Throwable.class, onThrowable = Throwable.class)
    public static void onExit(
            @Advice.Thrown Throwable throwable,
            @Advice.Return Object result,
            @Advice.Local("otelSpan") Span span,
            @Advice.Local("otelScope") Scope scope) {

        if (scope != null) {
            scope.close();
        }

        if (span != null) {
            if (throwable != null) {
                span.setStatus(StatusCode.ERROR, throwable.getMessage());
                span.recordException(throwable);
            } else {
                span.setStatus(StatusCode.OK);
            }
            span.end();
        }
    }
}
