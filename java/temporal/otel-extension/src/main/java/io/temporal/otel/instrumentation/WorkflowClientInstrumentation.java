package io.temporal.otel.instrumentation;

import io.opentelemetry.javaagent.extension.instrumentation.TypeInstrumentation;
import io.opentelemetry.javaagent.extension.instrumentation.TypeTransformer;
import io.temporal.otel.advice.WorkflowStartAdvice;
import io.temporal.otel.advice.WorkflowExecuteAdvice;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.matcher.ElementMatcher;

import static net.bytebuddy.matcher.ElementMatchers.*;

/**
 * Instruments WorkflowClient to create CLIENT spans for workflow operations.
 *
 * Target methods:
 * - WorkflowStub.start() - async workflow start
 * - WorkflowStub.execute() - sync workflow execution
 */
public class WorkflowClientInstrumentation implements TypeInstrumentation {

    @Override
    public ElementMatcher<TypeDescription> typeMatcher() {
        // Target the internal WorkflowInvocationHandler that handles all workflow method calls
        return named("io.temporal.internal.client.RootWorkflowClientInvoker");
    }

    @Override
    public void transform(TypeTransformer transformer) {
        // Instrument the start method for async workflow execution
        transformer.applyAdviceToMethod(
            named("start")
                .and(takesArguments(1))
                .and(isPublic()),
            WorkflowStartAdvice.class.getName()
        );

        // Instrument execute for sync workflow execution
        transformer.applyAdviceToMethod(
            named("execute")
                .and(takesArguments(1))
                .and(isPublic()),
            WorkflowExecuteAdvice.class.getName()
        );
    }
}
