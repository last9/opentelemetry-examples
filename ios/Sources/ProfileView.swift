import SwiftUI
import Last9RUM

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Profile Tab — user identification, span attributes, custom events, view /
//  flush control, session info, active SDK config, and a debug-log sheet.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ProfileView: View {
    @State private var loggedIn = false
    @State private var sessionId: String?
    @State private var debugVisible = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                FeatureBadge(features: [
                    "User Identification (identify / clearUser)",
                    "Session Tracking (4h max / 30min inactivity)",
                    "Head-based Sampling (sampleRate)",
                    "Global Span Attributes",
                    "Custom Events (addEvent)",
                    "Resource Monitoring (CPU/memory)",
                    "Flush Control",
                ])

                profileCard
                Hint("identify() sets user.id and attributes (name, email, full_name, roles) as span attributes on all subsequent spans.")

                SectionHeader(title: "Global Span Attributes")
                Hint("spanAttributes() adds key-value pairs to every span. Useful for A/B test variants, feature flags, etc.")
                HStack(spacing: 12) {
                    ActionButton(icon: "🏷️", label: "Set Attrs") {
                        L9Rum.shared.spanAttributes([
                            "app.experiment": "checkout_v2",
                            "app.feature_flag": "new_cart_enabled",
                            "app.build_type": "debug",
                        ])
                        EventLog.shared.add("spanAttributes: experiment=checkout_v2")
                    }
                    ActionButton(icon: "🗑️", label: "Clear Attrs") {
                        L9Rum.shared.spanAttributes(nil)
                        EventLog.shared.add("spanAttributes: cleared")
                    }
                }

                SectionHeader(title: "Custom Events")
                Hint("addEvent() creates a span event with custom attributes.")
                HStack(spacing: 12) {
                    ActionButton(icon: "👆", label: "Button Click") {
                        L9Rum.shared.addEvent("button_click", attributes: [
                            "button": "purchase", "screen": "Profile", "value": 99.99,
                        ])
                        EventLog.shared.add("event: button_click (purchase)")
                    }
                    ActionButton(icon: "⚡", label: "Feature Used") {
                        L9Rum.shared.addEvent("feature_used", attributes: [
                            "feature": "dark_mode", "enabled": true, "platform": "ios",
                        ])
                        EventLog.shared.add("event: feature_used (dark_mode)")
                    }
                }

                SectionHeader(title: "View & Export Control")
                HStack(spacing: 12) {
                    ActionButton(icon: "📱", label: "Set View Name") {
                        L9Rum.shared.setViewName("CustomViewName")
                        EventLog.shared.add("setViewName: CustomViewName")
                    }
                    ActionButton(icon: "📤", label: "Flush") {
                        L9Rum.shared.flush()
                        EventLog.shared.add("flush() — exported pending spans")
                    }
                }

                SectionHeader(title: "Session Info")
                sessionCard

                SectionHeader(title: "Active SDK Config")
                configCard

                if !RUMConfig.isConfigured {
                    Text("⚠️ Secrets.xcconfig still has placeholder values. Fill in your Last9 token to export data.")
                        .font(.footnote).foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { debugVisible = true } label: { Text("📋") }
                }
            }
            .sheet(isPresented: $debugVisible) { DebugLogSheet() }
        }
        .onAppear { sessionId = L9Rum.shared.getSessionId() }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(spacing: 10) {
            Avatar(initials: loggedIn ? "PP" : "?")
            Text(loggedIn ? "Piyush Pawar" : "Guest User")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(loggedIn ? "piyush@last9.io" : "Not signed in")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            if loggedIn {
                OutlineButton(title: "Sign Out") {
                    L9Rum.shared.clearUser()
                    loggedIn = false
                    EventLog.shared.add("clearUser()")
                }
            } else {
                PrimaryButton(title: "Sign In") {
                    L9Rum.shared.identify(userId: "piyush-01", attributes: [
                        "name": "Piyush",
                        "email": "piyush@last9.io",
                        "full_name": "Piyush Pawar",
                        "roles": ["developer", "admin"],
                    ])
                    loggedIn = true
                    sessionId = L9Rum.shared.getSessionId()
                    EventLog.shared.add("identify: Piyush Pawar (piyush-01)")
                }
                .fixedSize()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 16)
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session ID")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(sessionId ?? "loading…")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
            Text("Sessions visible at: RUM → Sessions in the Last9 dashboard.\nSession timeout: 4h max / 30min inactivity.")
                .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
            Button("Refresh") { sessionId = L9Rum.shared.getSessionId() }
                .font(.system(size: 11, weight: .semibold)).tint(Theme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var configRows: [(String, String)] {
        [
            ("serviceName", RUMConfig.serviceName),
            ("serviceVersion", RUMConfig.serviceVersion),
            ("appBuildId", RUMConfig.appBuildId),
            ("environment", RUMConfig.deploymentEnvironment),
            ("sampleRate", "\(RUMConfig.sampleRate)%"),
            ("networkInstrumentation", "true"),
            ("propagationMode", RUMConfig.propagationMode),
            ("errorInstrumentation", "true"),
            ("resourceMonitoring", "true"),
            ("baggage", "true"),
            ("isolateTracePerRequest", "false"),
        ]
    }

    private var configCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(configRows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    Text(row.0).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(row.1).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .padding(.vertical, 5)
                if idx < configRows.count - 1 { Divider().background(Color(.systemGray6)) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

/// Modal showing the global event log.
struct DebugLogSheet: View {
    @ObservedObject private var log = EventLog.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if log.entries.isEmpty {
                        Hint("No events yet")
                    } else {
                        ForEach(log.entries) { e in
                            (Text("\(e.ts) ").foregroundColor(Theme.textSecondary)
                             + Text(e.msg).foregroundColor(Theme.textPrimary))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 1)
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(.systemGray6))
            .navigationTitle("Event Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
