package io.last9.rumexample

import android.app.Application
import io.last9.rum.L9BaggageConfig
import io.last9.rum.L9NetworkIgnorePatterns
import io.last9.rum.L9PropagationMode
import io.last9.rum.L9Rum
import io.last9.rum.L9RumConfig
import io.last9.rum.L9UrlPattern

/**
 * Custom Application that initializes the Last9 RUM Android SDK at process start.
 *
 * Secret values (baseUrl, clientToken, origin) come from local.properties via
 * BuildConfig (see app/build.gradle.kts). Everything else mirrors the React
 * Native reference app's rich config so the two examples behave identically.
 */
class RumExampleApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        L9Rum.initialize(
            this,
            L9RumConfig(
                // --- From local.properties (git-ignored) ---
                baseUrl = BuildConfig.LAST9_BASE_URL,
                clientToken = BuildConfig.LAST9_CLIENT_TOKEN,
                origin = BuildConfig.LAST9_ORIGIN,

                // --- Identity / environment ---
                serviceName = "rum-android-example",
                serviceVersion = "1.0.0",
                appBuildId = "1.0.0-dev",
                deploymentEnvironment = "development",

                // --- Sampling / logging ---
                sampleRate = 100,
                debugLogs = true,

                // --- Network & error auto-instrumentation ---
                networkInstrumentation = true,
                errorInstrumentation = true,

                // --- Resource monitoring (CPU/memory) ---
                resourceMonitoringEnabled = true,
                resourceSamplingIntervalMs = 5_000L,

                // --- ANR detection ---
                anrDetectionEnabled = true,
                anrThresholdMs = 5_000L,

                // Keep network spans on the view's trace so they surface in the
                // Sessions → APIs tab (which filters child spans by traceId).
                isolateTracePerRequest = false,

                // Only suppress image/CDN resources; keep public API calls visible.
                propagationMode = L9PropagationMode.PRESERVE,
                ignorePatterns = L9NetworkIgnorePatterns(
                    fullUrl = listOf(
                        L9UrlPattern.Regex("^https://images\\.pexels\\.com/photos/", flags = "i"),
                    ),
                    pathname = listOf(
                        L9UrlPattern.Regex("\\.(png|jpe?g|webp)$", flags = "i"),
                    ),
                    hostname = listOf(
                        L9UrlPattern.Regex("(^|\\.)loremflickr\\.com$", flags = "i"),
                    ),
                ),

                // Custom resource attributes.
                resourceAttributes = mapOf(
                    "app.platform" to "android",
                    "device.type" to "mobile",
                ),

                // W3C Baggage propagation.
                baggage = L9BaggageConfig(
                    enabled = true,
                    allowedKeys = listOf(
                        "session.id",
                        "user.id",
                        "deployment.environment",
                        "service.name",
                    ),
                ),
            ),
        )
    }
}
