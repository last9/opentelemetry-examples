package io.temporal.otel.instrumentation;

import io.opentelemetry.javaagent.extension.instrumentation.TypeInstrumentation;
import io.opentelemetry.javaagent.extension.instrumentation.TypeTransformer;
import io.temporal.otel.advice.ActivityExecuteAdvice;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.matcher.ElementMatcher;

import static net.bytebuddy.matcher.ElementMatchers.*;

/**
 * Instruments Activity execution to create SERVER spans.
 *
 * Target: POJOActivityTaskHandler.handle() - where activities are executed on the worker
 */
public class ActivityTaskHandlerInstrumentation implements TypeInstrumentation {

    @Override
    public ElementMatcher<TypeDescription> typeMatcher() {
        return named("io.temporal.internal.activity.POJOActivityTaskHandler");
    }

    @Override
    public void transform(TypeTransformer transformer) {
        // Instrument the handle method that executes activities
        transformer.applyAdviceToMethod(
            named("handle")
                .and(takesArguments(2))  // (ActivityTask, Scope)
                .and(isPublic()),
            ActivityExecuteAdvice.class.getName()
        );
    }
}
