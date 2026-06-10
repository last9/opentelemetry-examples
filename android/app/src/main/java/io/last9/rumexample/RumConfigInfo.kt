package io.last9.rumexample

/**
 * Non-secret snapshot of the active SDK config, surfaced read-only to the
 * Profile screen's "Active SDK Config" card. Keeps the values in one place so
 * the card stays in sync with [RumExampleApplication]. Secrets are never
 * included here.
 */
object RumConfigInfo {
    const val SERVICE_NAME = "rum-android-example"
    const val SERVICE_VERSION = "1.0.0"
    const val APP_BUILD_ID = "1.0.0-dev"
    const val ENVIRONMENT = "development"
    const val SAMPLE_RATE = 100
    const val NETWORK_INSTRUMENTATION = true
    const val PROPAGATION_MODE = "PRESERVE"
    const val ERROR_INSTRUMENTATION = true
    const val RESOURCE_MONITORING = true
    const val ANR_DETECTION = true
    const val BAGGAGE_ENABLED = true
    const val ISOLATE_TRACE_PER_REQUEST = false

    /** Ordered key/value rows for the config card. */
    val rows: List<Pair<String, String>> = listOf(
        "serviceName" to SERVICE_NAME,
        "serviceVersion" to SERVICE_VERSION,
        "appBuildId" to APP_BUILD_ID,
        "environment" to ENVIRONMENT,
        "sampleRate" to "$SAMPLE_RATE%",
        "networkInstrumentation" to "$NETWORK_INSTRUMENTATION",
        "propagationMode" to PROPAGATION_MODE,
        "errorInstrumentation" to "$ERROR_INSTRUMENTATION",
        "resourceMonitoring" to "$RESOURCE_MONITORING",
        "anrDetection" to "$ANR_DETECTION",
        "baggage" to "$BAGGAGE_ENABLED",
        "isolateTracePerRequest" to "$ISOLATE_TRACE_PER_REQUEST",
    )
}
