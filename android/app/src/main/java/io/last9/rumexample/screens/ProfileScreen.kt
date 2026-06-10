package io.last9.rumexample.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.last9.rum.L9Rum
import io.last9.rumexample.EventLog
import io.last9.rumexample.RumConfigInfo
import io.last9.rumexample.ui.ActionButton
import io.last9.rumexample.ui.Avatar
import io.last9.rumexample.ui.ConfigRow
import io.last9.rumexample.ui.DebugLogModal
import io.last9.rumexample.ui.FeatureBadge
import io.last9.rumexample.ui.Hint
import io.last9.rumexample.ui.L9Card
import io.last9.rumexample.ui.L9Theme
import io.last9.rumexample.ui.MonoText
import io.last9.rumexample.ui.OutlineButton
import io.last9.rumexample.ui.PrimaryButton
import io.last9.rumexample.ui.ScreenHeader
import io.last9.rumexample.ui.SectionTitle

/**
 * Profile tab — identify/clearUser, span attributes, custom events, view name +
 * flush, session info, the active SDK config card, and a debug-log modal showing
 * the global [EventLog]. Mirrors the reference Profile screen.
 */
@Composable
fun ProfileScreen() {
    var loggedIn by remember { mutableStateOf(false) }
    var sessionId by remember { mutableStateOf(L9Rum.getSessionId() ?: "loading…") }
    var debugVisible by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().background(L9Theme.ScreenBg)) {
        ScreenHeader(
            "Profile",
            trailing = {
                Text(
                    "📋",
                    fontSize = 18.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .clickable { debugVisible = true }
                        .padding(4.dp),
                )
            },
        )
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FeatureBadge(
                features = listOf(
                    "User Identification (identify / clearUser)",
                    "Session Tracking (4h max / 30min inactivity)",
                    "Head-based Sampling (sampleRate)",
                    "Global Span Attributes",
                    "Custom Events (addEvent)",
                    "Resource Monitoring (CPU/memory)",
                    "Flush Control",
                ),
            )

            // User card
            L9Card {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Avatar(if (loggedIn) "PW" else "?")
                    Spacer(Modifier.size(10.dp))
                    Text(
                        if (loggedIn) "Piyush Pawar" else "Guest User",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = L9Theme.TitleText,
                    )
                    Spacer(Modifier.size(2.dp))
                    Text(
                        if (loggedIn) "piyush@last9.io" else "Not signed in",
                        fontSize = 13.sp,
                        color = L9Theme.HintText,
                    )
                    Spacer(Modifier.size(14.dp))
                    if (loggedIn) {
                        OutlineButton("Sign Out", onClick = {
                            L9Rum.clearUser()
                            loggedIn = false
                            EventLog.add("clearUser()")
                        })
                    } else {
                        PrimaryButton("Sign In", onClick = {
                            L9Rum.identify(
                                "piyush-01",
                                mapOf(
                                    "name" to "Piyush",
                                    "email" to "piyush@last9.io",
                                    "full_name" to "Piyush Pawar",
                                    "roles" to listOf("developer", "admin"),
                                ),
                            )
                            loggedIn = true
                            EventLog.add("identify: Piyush Pawar (piyush-01)")
                        })
                    }
                }
            }
            Hint("identify() sets user.id, user.name, user.email, user.full_name, user.roles as span attributes on all subsequent spans.")

            // Span attributes
            SectionTitle("Global Span Attributes")
            Hint("spanAttributes() adds key-value pairs to every span. Useful for A/B test variants, feature flags, etc.")
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ActionButton(
                    icon = "🏷️",
                    label = "Set Attrs",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        L9Rum.spanAttributes(
                            mapOf(
                                "app.experiment" to "checkout_v2",
                                "app.feature_flag" to "new_cart_enabled",
                                "app.build_type" to "debug",
                            ),
                        )
                        EventLog.add("spanAttributes: experiment=checkout_v2")
                    },
                )
                ActionButton(
                    icon = "🗑️",
                    label = "Clear Attrs",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        L9Rum.spanAttributes(null)
                        EventLog.add("spanAttributes: cleared")
                    },
                )
            }

            // Custom events
            SectionTitle("Custom Events")
            Hint("addEvent() creates a span event with custom attributes.")
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ActionButton(
                    icon = "👆",
                    label = "Button Click",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        L9Rum.addEvent(
                            "button_click",
                            mapOf("button" to "purchase", "screen" to "Profile", "value" to 99.99),
                        )
                        EventLog.add("event: button_click (purchase)")
                    },
                )
                ActionButton(
                    icon = "⚡",
                    label = "Feature Used",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        L9Rum.addEvent(
                            "feature_used",
                            mapOf("feature" to "dark_mode", "enabled" to true, "platform" to "android"),
                        )
                        EventLog.add("event: feature_used (dark_mode)")
                    },
                )
            }

            // View / flush
            SectionTitle("View & Export Control")
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ActionButton(
                    icon = "📱",
                    label = "Set View Name",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        L9Rum.setViewName("CustomViewName")
                        EventLog.add("setViewName: CustomViewName")
                    },
                )
                ActionButton(
                    icon = "📤",
                    label = "Flush",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        L9Rum.flush()
                        EventLog.add("flush() — exported pending spans")
                    },
                )
            }

            // Session info
            SectionTitle("Session Info")
            L9Card(onClick = { sessionId = L9Rum.getSessionId() ?: "(none)" }) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text("SESSION ID", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = L9Theme.Accent)
                    Spacer(Modifier.size(4.dp))
                    MonoText(sessionId)
                    Spacer(Modifier.size(6.dp))
                    Text(
                        "Sessions visible at RUM → Sessions in the Last9 dashboard.\nSession timeout: 4h max / 30min inactivity. Tap to refresh.",
                        fontSize = 10.sp,
                        color = L9Theme.HintText,
                    )
                }
            }

            // SDK config
            SectionTitle("Active SDK Config")
            L9Card {
                Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) {
                    RumConfigInfo.rows.forEachIndexed { i, (k, v) ->
                        ConfigRow(k, v, showDivider = i < RumConfigInfo.rows.lastIndex)
                    }
                }
            }

            Spacer(Modifier.size(8.dp))
        }
    }

    if (debugVisible) {
        DebugLogModal(entries = EventLog.entries, onDismiss = { debugVisible = false })
    }
}
