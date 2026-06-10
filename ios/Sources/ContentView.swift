import SwiftUI
import Last9RUM

/// Root tab bar — five tabs mirroring the React Native reference app:
/// Home 🏠, Network 🌐, WebView 🔗, Errors ⚠️, Profile 👤.
struct ContentView: View {
    var body: some View {
        TabView {
            HomeTab()
                .tabItem { Label("Home", systemImage: "house") }
            NetworkView()
                .tabItem { Label("Network", systemImage: "globe") }
            WebViewTab()
                .tabItem { Label("WebView", systemImage: "link") }
            ErrorsView()
                .tabItem { Label("Errors", systemImage: "exclamationmark.triangle") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .tint(Theme.accent)
    }
}
