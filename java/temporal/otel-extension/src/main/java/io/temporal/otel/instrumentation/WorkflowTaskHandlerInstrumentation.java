package io.temporal.otel.instrumentation;

import io.opentelemetry.javaagent.extension.instrumentation.TypeInstrumentation;
import io.opentelemetry.javaagent.extension.instrumentation.TypeTransformer;
import io.temporal.otel.advice.WorkflowRunAdvice;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.matcher.ElementMatcher;

import static net.bytebuddy.matcher.ElementMatchers.*;

/**
 * Instruments Workflow execution to create SERVER spans.
 *
 * Target: ReplayWorkflowTaskHandler - where workflows are executed/replayed on the worker
 */
public class WorkflowTaskHandlerInstrumentation implements TypeInstrumentation {

    @Override
    public ElementMatcher<TypeDescription> typeMatcher() {
        return named("io.temporal.internal.replay.ReplayWorkflowTaskHandler");
    }

    @Override
    public void transform(TypeTransformer transformer) {
        // Instrument handleWorkflowTask for workflow execution
        transformer.applyAdviceToMethod(
            named("handleWorkflowTask")
                .and(isPublic()),
            WorkflowRunAdvice.class.getName()
        );
    }
}
