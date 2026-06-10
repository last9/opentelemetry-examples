import SwiftUI
import WebKit
import Last9RUM

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  WebView Tab — native session/view correlation for Browser RUM in WebViews.
//  Loads https://app.last9.io/ in a WKWebView, injects the SDK's native
//  context script (getWebViewInjectedJavaScript) + a Browser-RUM bootstrap, and
//  calls instrument(webView:) so the page's spans share the native session.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private let WEBVIEW_TEST_URL = "https://app.last9.io/"

/// Browser-RUM bootstrap analogous to the RN reference app's
/// `WEBVIEW_RUM_BOOTSTRAP`. It waits for the native context (written by the
/// SDK's injected script) and `window.L9RUM`, then posts the context back to
/// native via `window.webkit.messageHandlers.l9native`. Browser RUM itself is
/// auto-loaded by the SDK (webViewAutoLoadBrowserRum=true), so this script only
/// adds the context-probe round-trip the demo UI displays.
private let WEBVIEW_RUM_BOOTSTRAP = """
(function() {
  if (window.__L9_WEBVIEW_PROBE_BOOTSTRAPPED) return true;
  window.__L9_WEBVIEW_PROBE_BOOTSTRAPPED = true;

  function postContext(reason) {
    try {
      window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.l9native &&
        window.webkit.messageHandlers.l9native.postMessage(JSON.stringify({
          reason: reason,
          href: window.location.href,
          hasL9RUM: !!window.L9RUM,
          context: window.__LAST9_RUM_NATIVE_CONTEXT || null
        }));
    } catch (_) {}
  }

  function pollReady(attempts) {
    if (window.L9RUM && window.__LAST9_RUM_NATIVE_CONTEXT) {
      try {
        window.L9RUM.addEvent && window.L9RUM.addEvent('webview_real_page_loaded', {
          source: 'ios-wkwebview-demo'
        });
      } catch (_) {}
      postContext('browser-rum-ready');
      return;
    }
    if (attempts <= 0) { postContext('browser-rum-timeout'); return; }
    setTimeout(function() { pollReady(attempts - 1); }, 150);
  }

  window.addEventListener('l9rum:native_context', function() {
    postContext('l9rum:native_context');
  });

  pollReady(40);
  setTimeout(function() { postContext('initial-page-load'); }, 500);
})();
true;
"""

struct WebViewTab: View {
    @StateObject private var model = WebViewModel()

    var body: some View {
        NavigationStack {
            ScreenScroll {
                FeatureBadge(features: [
                    "getWebViewInjectedJavaScript() native context helper",
                    "instrument(webView:) re-injects context on navigation",
                    "Native session.id shared with Browser RUM in the page",
                    "Native view.id stamped as native.view.id",
                ])
                Hint("This screen loads the Last9 dashboard in a real WKWebView. The app injects native session/view context and auto-loads Browser RUM on the page, then the page posts its context back to native.")

                PrimaryButton(title: "Refresh WebView Context") { model.refresh() }

                SectionHeader(title: "Last Context Probe")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Native WebView Context")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text("sessionId: \(model.sessionId ?? "waiting…")")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                    Text("native.view.id: \(model.viewId ?? "waiting…")")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                Text(model.contextProbe)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .cardStyle(cornerRadius: 10)

                SectionHeader(title: "Actual WebView")
                WebViewContainer(model: model)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    .padding(.bottom, 24)
            }
            .navigationTitle("WebView Correlation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Holds the WebView state + receives the JS context-probe messages.
@MainActor
final class WebViewModel: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var contextProbe = "Waiting for WebView context…"
    @Published var sessionId: String?
    @Published var viewId: String?

    /// Bumped to force the WebView to reload.
    @Published var reloadToken = 0

    func refresh() {
        L9Rum.shared.startView("WebViewSessionCorrelation")
        EventLog.shared.add("WebView context refresh requested")
        reloadToken += 1
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        Task { @MainActor in self.handle(body) }
    }

    private func handle(_ body: String) {
        contextProbe = body
        if let data = body.data(using: .utf8),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let context = payload["context"] as? [String: Any] {
            let sid = context["sessionId"] as? String
            let vid = (context["nativeViewId"] as? String) ?? (context["viewId"] as? String)
            sessionId = sid
            viewId = vid
            EventLog.shared.add("WebView context → session:\(sid ?? "missing") view:\(vid ?? "missing")")
        }
    }
}

/// Bridges a configured `WKWebView` into SwiftUI.
struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        // Start the native view BEFORE the WebView so the SDK has an active
        // view to stamp as the WebView host (view.type=webview, native.view.id).
        L9Rum.shared.startView("WebViewSessionCorrelation")

        let controller = WKUserContentController()
        controller.add(model, name: "l9native")

        // Document-start injection of the SDK's native-context script + the
        // demo's context-probe bootstrap.
        let injected = L9Rum.shared.getWebViewInjectedJavaScript() + "\n" + WEBVIEW_RUM_BOOTSTRAP
        EventLog.shared.add("WebView injected JS loaded (\(injected.count) chars)")
        controller.addUserScript(WKUserScript(source: injected,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)

        // Forwarding navigation delegate that re-injects context on every
        // committed navigation and auto-loads Browser RUM.
        L9Rum.shared.instrument(webView: webView)

        webView.load(URLRequest(url: URL(string: WEBVIEW_TEST_URL)!))
        context.coordinator.lastReloadToken = model.reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != model.reloadToken {
            context.coordinator.lastReloadToken = model.reloadToken
            L9Rum.shared.instrument(webView: webView)
            webView.reload()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastReloadToken = -1
    }
}
