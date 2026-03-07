package io.temporal.otel.advice;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import net.bytebuddy.asm.Advice;

/**
 * ByteBuddy advice for Activity execution on workers - creates SERVER spans.
 *
 * This intercepts POJOActivityTaskHandler.handle() which executes activities.
 */
@SuppressWarnings("unused")
public class ActivityExecuteAdvice {

    private static final Tracer tracer = GlobalOpenTelemetry.getTracer("io.temporal");

    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static void onEnter(
            @Advice.Argument(0) Object activityTask,
            @Advice.Local("otelSpan") Span span,
            @Advice.Local("otelScope") Scope scope) {

        String activityType = "UnknownActivity";
        String workflowId = "unknown";
        String activityId = "unknown";

        try {
            // Extract activity info via reflection to avoid compile-time dependency
            if (activityTask != null) {
                var getActivityType = activityTask.getClass().getMethod("getActivityType");
                var activityTypeObj = getActivityType.invoke(activityTask);
                if (activityTypeObj != null) {
                    var getName = activityTypeObj.getClass().getMethod("getName");
                    activityType = (String) getName.invoke(activityTypeObj);
                }

                var getWorkflowExecution = activityTask.getClass().getMethod("getWorkflowExecution");
                var execution = getWorkflowExecution.invoke(activityTask);
                if (execution != null) {
                    var getWorkflowId = execution.getClass().getMethod("getWorkflowId");
                    workflowId = (String) getWorkflowId.invoke(execution);
                }

                var getActivityId = activityTask.getClass().getMethod("getActivityId");
                activityId = (String) getActivityId.invoke(activityTask);
            }
        } catch (Exception ignored) {
            // Reflection may fail, use defaults
        }

        span = tracer.spanBuilder("RunActivity:" + activityType)
            .setSpanKind(SpanKind.SERVER)  // SERVER - we're receiving work
            .setAttribute("temporal.activity.type", activityType)
            .setAttribute("temporal.activity.id", activityId)
            .setAttribute("temporal.workflow.id", workflowId)
            .setAttribute("temporal.operation", "RUN_ACTIVITY")
            .setAttribute("rpc.system", "temporal")
            .setAttribute("rpc.service", "ActivityTask")
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
