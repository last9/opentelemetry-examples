package io.temporal.otel.advice;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import net.bytebuddy.asm.Advice;

/**
 * ByteBuddy advice for synchronous workflow execution - creates CLIENT spans.
 */
@SuppressWarnings("unused")
public class WorkflowExecuteAdvice {

    private static final Tracer tracer = GlobalOpenTelemetry.getTracer("io.temporal");

    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static void onEnter(
            @Advice.This Object self,
            @Advice.Argument(0) Object functions,
            @Advice.Local("otelSpan") Span span,
            @Advice.Local("otelScope") Scope scope) {

        String workflowType = "UnknownWorkflow";

        try {
            if (functions != null) {
                workflowType = functions.getClass().getSimpleName();
            }
        } catch (Exception ignored) {
        }

        span = tracer.spanBuilder("ExecuteWorkflow:" + workflowType)
            .setSpanKind(SpanKind.CLIENT)
            .setAttribute("temporal.workflow.type", workflowType)
            .setAttribute("temporal.operation", "EXECUTE_WORKFLOW")
            .setAttribute("rpc.system", "temporal")
            .setAttribute("rpc.service", "WorkflowService")
            .setAttribute("rpc.method", "ExecuteWorkflow")
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
