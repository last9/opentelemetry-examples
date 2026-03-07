package io.temporal.otel.advice;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import net.bytebuddy.asm.Advice;

/**
 * ByteBuddy advice for Workflow execution on workers - creates SERVER spans.
 *
 * This intercepts ReplayWorkflowTaskHandler.handleWorkflowTask() which executes workflows.
 */
@SuppressWarnings("unused")
public class WorkflowRunAdvice {

    private static final Tracer tracer = GlobalOpenTelemetry.getTracer("io.temporal");

    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static void onEnter(
            @Advice.Argument(0) Object workflowTask,
            @Advice.Local("otelSpan") Span span,
            @Advice.Local("otelScope") Scope scope) {

        String workflowType = "UnknownWorkflow";
        String workflowId = "unknown";
        String runId = "unknown";

        try {
            // Extract workflow info via reflection
            if (workflowTask != null) {
                var getWorkflowType = workflowTask.getClass().getMethod("getWorkflowType");
                var workflowTypeObj = getWorkflowType.invoke(workflowTask);
                if (workflowTypeObj != null) {
                    var getName = workflowTypeObj.getClass().getMethod("getName");
                    workflowType = (String) getName.invoke(workflowTypeObj);
                }

                var getWorkflowExecution = workflowTask.getClass().getMethod("getWorkflowExecution");
                var execution = getWorkflowExecution.invoke(workflowTask);
                if (execution != null) {
                    var getWorkflowId = execution.getClass().getMethod("getWorkflowId");
                    workflowId = (String) getWorkflowId.invoke(execution);

                    var getRunId = execution.getClass().getMethod("getRunId");
                    runId = (String) getRunId.invoke(execution);
                }
            }
        } catch (Exception ignored) {
            // Reflection may fail, use defaults
        }

        span = tracer.spanBuilder("RunWorkflow:" + workflowType)
            .setSpanKind(SpanKind.SERVER)  // SERVER - we're receiving work
            .setAttribute("temporal.workflow.type", workflowType)
            .setAttribute("temporal.workflow.id", workflowId)
            .setAttribute("temporal.run.id", runId)
            .setAttribute("temporal.operation", "RUN_WORKFLOW")
            .setAttribute("rpc.system", "temporal")
            .setAttribute("rpc.service", "WorkflowTask")
            .setAttribute("rpc.method", "Execute")
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
