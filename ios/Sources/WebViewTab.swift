import SwiftUI
import WebKit
import Last9RUM

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  WebView Harness — ENG-1844 / 1837 / 1847 / 1848 against local 1.6.9 SDK.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private let LIVE_URL = "https://app.last9.io/"

private let HARNESS_HTML = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Last9 WebView Harness</title>
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; margin: 16px; color: #111; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    p { font-size: 13px; color: #444; }
    button { display: block; width: 100%; margin: 8px 0; padding: 12px; font-size: 14px;
             border-radius: 8px; border: 1px solid #ddd; background: #f7f7f7; }
    code { background: #eee; padding: 2px 4px; border-radius: 4px; font-size: 12px; }
  </style>
</head>
<body>
  <h1>Last9 WebView Harness</h1>
  <p>Path: <code id="path"></code></p>
  <button onclick="goHash('/labs')">Hash #/labs</button>
  <button onclick="goHash('/labs/tests')">Hash #/labs/tests</button>
  <button onclick="goHash('/labs/tests?city=test')">Hash query-ish</button>
  <button onclick="goHash('/health-record')">Hash #/health-record</button>
  <button onclick="pushSpa('/checkout')">pushState /checkout</button>
  <button onclick="history.back()">history.back()</button>
  <script>
    function show() {
      document.getElementById('path').textContent = location.pathname + location.search + location.hash;
    }
    function goHash(frag) { location.hash = frag; show(); }
    function pushSpa(path) {
      history.pushState({}, '', path);
      window.dispatchEvent(new PopStateEvent('popstate'));
      show();
    }
    window.addEventListener('hashchange', show);
    window.addEventListener('popstate', show);
    show();
  </script>
</body>
</html>
"""

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
                    "Local 1.6.9 SDK (path rotate / resume fold / SPA / kill tombstone)",
                    "instrument(webView:) + getWebViewInjectedJavaScript()",
                    "Harness HTML: hash + pushState SPA",
                    "flush() without session rollover",
                ])
                Hint("1) Tap hash/pushState buttons → expect view.url updates.\n2) Leave WebView tab → return → fold, no bare host.\n3) Flush then force-quit → cold start tombstone + restore.")

                PrimaryButton(title: "Load harness HTML") { model.loadHarness() }
                PrimaryButton(title: "Load app.last9.io") { model.loadLive() }
                PrimaryButton(title: "flush() — export, keep session") {
                    L9Rum.shared.flush()
                    EventLog.shared.add("L9Rum.flush()")
                }
                PrimaryButton(title: "addEvent(WebView_shown)") {
                    L9Rum.shared.addEvent("WebView_shown", attributes: ["source": "ios-harness"])
                    EventLog.shared.add("addEvent WebView_shown")
                }
                PrimaryButton(title: "Reload") { model.refresh() }

                SectionHeader(title: "Last Context Probe")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Native WebView Context")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text("sessionId: \(model.sessionId ?? "waiting…")")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                    Text("native.view.id: \(model.viewId ?? "waiting…")")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                    Text("mode: \(model.mode)")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
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
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    .padding(.bottom, 24)
            }
            .navigationTitle("WebView Harness")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor
final class WebViewModel: NSObject, ObservableObject, WKScriptMessageHandler {
    enum Mode { case harness, live }

    @Published var contextProbe = "Waiting for WebView context…"
    @Published var sessionId: String?
    @Published var viewId: String?
    @Published var reloadToken = 0
    @Published var mode: Mode = .harness

    func loadHarness() {
        mode = .harness
        refresh()
    }

    func loadLive() {
        mode = .live
        refresh()
    }

    func refresh() {
        L9Rum.shared.startView("WebViewHarness")
        EventLog.shared.add("WebView refresh mode=\(mode)")
        reloadToken += 1
    }

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

struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        L9Rum.shared.startView("WebViewHarness")

        let controller = WKUserContentController()
        controller.add(model, name: "l9native")

        let injected = L9Rum.shared.getWebViewInjectedJavaScript() + "\n" + WEBVIEW_RUM_BOOTSTRAP
        EventLog.shared.add("WebView injected JS loaded (\(injected.count) chars)")
        controller.addUserScript(WKUserScript(source: injected,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        L9Rum.shared.instrument(webView: webView)
        load(into: webView)
        context.coordinator.lastReloadToken = model.reloadToken
        context.coordinator.lastMode = model.mode
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != model.reloadToken
            || context.coordinator.lastMode != model.mode {
            context.coordinator.lastReloadToken = model.reloadToken
            context.coordinator.lastMode = model.mode
            L9Rum.shared.instrument(webView: webView)
            load(into: webView)
        }
    }

    private func load(into webView: WKWebView) {
        switch model.mode {
        case .harness:
            webView.loadHTMLString(HARNESS_HTML, baseURL: URL(string: "https://harness.local/"))
        case .live:
            webView.load(URLRequest(url: URL(string: LIVE_URL)!))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastReloadToken = -1
        var lastMode: WebViewModel.Mode = .harness
    }
}
