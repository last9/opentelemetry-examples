package io.temporal.otel.instrumentation;

import com.google.auto.service.AutoService;
import io.opentelemetry.javaagent.extension.instrumentation.InstrumentationModule;
import io.opentelemetry.javaagent.extension.instrumentation.TypeInstrumentation;
import net.bytebuddy.matcher.ElementMatcher;

import java.util.Arrays;
import java.util.List;

import static io.opentelemetry.javaagent.extension.matcher.AgentElementMatchers.hasClassesNamed;

/**
 * OpenTelemetry Java Agent instrumentation module for Temporal SDK.
 *
 * This module provides zero-code instrumentation for:
 * - Workflow client operations (CLIENT spans)
 * - Activity execution (SERVER spans)
 * - Workflow execution (SERVER spans)
 *
 * Usage:
 *   java -javaagent:opentelemetry-javaagent.jar \
 *        -Dotel.javaagent.extensions=temporal-otel-extension.jar \
 *        -jar your-app.jar
 */
@AutoService(InstrumentationModule.class)
public class TemporalInstrumentationModule extends InstrumentationModule {

    public TemporalInstrumentationModule() {
        super("temporal", "temporal-sdk", "temporal-1.0");
    }

    @Override
    public List<TypeInstrumentation> typeInstrumentations() {
        return Arrays.asList(
            new WorkflowClientInstrumentation(),
            new ActivityTaskHandlerInstrumentation(),
            new WorkflowTaskHandlerInstrumentation()
        );
    }

    @Override
    public ElementMatcher.Junction<ClassLoader> classLoaderMatcher() {
        // Only apply if Temporal SDK is present
        return hasClassesNamed("io.temporal.client.WorkflowClient");
    }

    @Override
    public boolean isHelperClass(String className) {
        return className.startsWith("io.temporal.otel.");
    }
}
