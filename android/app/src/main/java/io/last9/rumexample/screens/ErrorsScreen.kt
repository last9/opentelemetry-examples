package io.last9.rumexample.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import io.last9.rum.L9Rum
import io.last9.rumexample.EventLog
import io.last9.rumexample.ui.ErrorButton
import io.last9.rumexample.ui.FeatureBadge
import io.last9.rumexample.ui.Hint
import io.last9.rumexample.ui.ScreenHeader

/**
 * Errors tab — the same set of error buttons as the reference (captureError with
 * context, TypeError/NPE, network error, "unhandled" promise rejection analogue,
 * deep stack, ANR simulation, burst) plus an uncaught crash. All log to the
 * global [EventLog].
 */
@Composable
fun ErrorsScreen() {
    Column(modifier = Modifier.fillMaxSize().background(io.last9.rumexample.ui.L9Theme.ScreenBg)) {
        ScreenHeader("Errors")
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            FeatureBadge(
                features = listOf(
                    "Manual Error Capture (captureError)",
                    "Caught exceptions with context",
                    "Network error capture",
                    "ANR Detection (Android, 5s threshold)",
                    "Stack Traces with Context",
                ),
            )
            Hint("errorInstrumentation=true auto-captures uncaught exceptions. anrDetectionEnabled=true watches for main-thread blocks >5s.")

            ErrorButton(
                title = "Capture Error (with context)",
                subtitle = "L9Rum.captureError(err, { screen, severity, user_action })",
                accent = Color(0xFFFF6B6B),
                onClick = {
                    L9Rum.captureError(
                        RuntimeException("Checkout failed: payment gateway timeout"),
                        mapOf(
                            "screen" to "Checkout",
                            "severity" to "high",
                            "user_action" to "submit_payment",
                            "cart_total" to 149.99,
                        ),
                    )
                    EventLog.add("captureError: payment gateway timeout")
                },
            )

            ErrorButton(
                title = "Capture TypeError",
                subtitle = "Simulates accessing property of null",
                accent = Color(0xFFFF9F43),
                onClick = {
                    try {
                        val obj: String? = null
                        obj!!.length
                    } catch (e: Exception) {
                        L9Rum.captureError(e, mapOf("screen" to "ErrorsDemo", "type" to "TypeError"))
                        EventLog.add("captureError: TypeError")
                    }
                },
            )

            ErrorButton(
                title = "Capture Network Error",
                subtitle = "Simulates a failed API call error",
                accent = Color(0xFFEE5A24),
                onClick = {
                    L9Rum.captureError(
                        RuntimeException("NetworkError: Failed to fetch /todos"),
                        mapOf(
                            "screen" to "Todos",
                            "endpoint" to "/todos",
                            "http_method" to "GET",
                            "retry_count" to 3,
                        ),
                    )
                    EventLog.add("captureError: NetworkError")
                },
            )

            ErrorButton(
                title = "Unhandled Rejection",
                subtitle = "Captures an error analogous to a promise rejection",
                accent = Color(0xFF6C5CE7),
                onClick = {
                    L9Rum.captureError(
                        RuntimeException("Unhandled: session token expired"),
                        mapOf("source" to "promise_rejection"),
                    )
                    EventLog.add("captureError: promise rejection")
                },
            )

            ErrorButton(
                title = "Capture Error with Stack Trace",
                subtitle = "Deep call stack to demonstrate trace capture",
                accent = Color(0xFFA29BFE),
                onClick = {
                    try {
                        level1()
                    } catch (e: Exception) {
                        L9Rum.captureError(e, mapOf("screen" to "ErrorsDemo", "stack_depth" to 3))
                        EventLog.add("captureError: deep stack trace")
                    }
                },
            )

            ErrorButton(
                title = "ANR Simulation (Android only)",
                subtitle = "Blocks the main thread for ~3s — ANR watchdog may fire if >5s",
                accent = Color(0xFFFD79A8),
                onClick = {
                    // Busy-wait on the main thread, exactly like the reference.
                    EventLog.add("starting ANR simulation (3s block)…")
                    val end = System.currentTimeMillis() + 3000
                    @Suppress("ControlFlowWithEmptyBody")
                    while (System.currentTimeMillis() < end) { /* block main thread */ }
                    EventLog.add("ANR simulation complete")
                },
            )

            ErrorButton(
                title = "Fire Multiple Errors (Burst)",
                subtitle = "5 rapid errors to test batching & export",
                accent = Color(0xFF00B894),
                onClick = {
                    for (i in 1..5) {
                        L9Rum.captureError(
                            RuntimeException("Burst error #$i"),
                            mapOf("index" to i, "screen" to "ErrorsDemo"),
                        )
                    }
                    EventLog.add("captureError: 5 burst errors")
                },
            )

            ErrorButton(
                title = "Throw Uncaught Exception",
                subtitle = "Crashes the app — auto-captured by errorInstrumentation",
                accent = Color(0xFFD63031),
                onClick = {
                    EventLog.add("throwing UNCAUGHT exception")
                    throw RuntimeException("Simulated UNCAUGHT exception from the Errors screen")
                },
            )

            Spacer(Modifier.size(8.dp))
        }
    }
}

// Deep call stack to demonstrate stack-trace capture.
private fun level1(): Nothing = level2()
private fun level2(): Nothing = level3()
private fun level3(): Nothing =
    throw RuntimeException("Deep stack: database connection pool exhausted")
