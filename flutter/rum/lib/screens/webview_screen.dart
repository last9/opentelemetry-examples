import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:last9_rum_flutter/last9_rum_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';
import '../event_log.dart';
import '../theme.dart';
import '../widgets.dart';

/// JS channel name the in-page bootstrap posts native-context probes to.
const String _kChannelName = 'L9Native';

/// A Browser-RUM bootstrap analogous to the reference app's
/// `WEBVIEW_RUM_BOOTSTRAP`. It loads @last9/rum into the page, initializes it
/// against the same baseUrl/clientToken, and posts the native context (written
/// by getWebViewInjectedJavaScript) back over the [_kChannelName] channel.
String _browserRumBootstrap() => '''
  (function() {
    if (window.__L9_WEBVIEW_RUM_BOOTSTRAPPED) return true;
    window.__L9_WEBVIEW_RUM_BOOTSTRAPPED = true;

    function postContext(reason) {
      try {
        var ctx = window.__LAST9_RUM_NATIVE_CONTEXT || null;
        window.$_kChannelName && window.$_kChannelName.postMessage(JSON.stringify({
          reason: reason,
          href: window.location.href,
          hasL9RUM: !!window.L9RUM,
          context: ctx
        }));
      } catch (_) {}
    }

    function initBrowserRum() {
      if (!window.L9RUM || !window.__LAST9_RUM_NATIVE_CONTEXT) {
        setTimeout(initBrowserRum, 100);
        return;
      }
      try {
        window.L9RUM.init({
          baseUrl: ${jsonEncode(kBaseUrl)},
          headers: { clientToken: ${jsonEncode(kClientToken)} },
          resourceAttributes: {
            serviceName: ${jsonEncode(kServiceName)},
            deploymentEnvironment: ${jsonEncode(kDeploymentEnvironment)},
            appVersion: ${jsonEncode(kServiceVersion)}
          },
          sampleRate: 100,
          debug: true,
          debugLogs: true
        });
        window.L9RUM.addEvent('webview_real_page_loaded', {
          source: 'flutter-webview-demo'
        });
        postContext('browser-rum-init');
      } catch (e) {
        postContext('browser-rum-init-error:' + (e && e.message ? e.message : e));
      }
    }

    function loadBrowserRum() {
      if (window.L9RUM) { initBrowserRum(); return; }
      var script = document.createElement('script');
      script.src = ${jsonEncode(kBrowserRumSdkUrl)};
      script.async = true;
      script.onload = initBrowserRum;
      script.onerror = function () { postContext('browser-rum-load-error'); };
      (document.head || document.documentElement).appendChild(script);
    }

    window.addEventListener('l9rum:native_context', function () {
      postContext('l9rum:native_context');
    });

    loadBrowserRum();
    setTimeout(function () { postContext('initial-page-load'); }, 500);
  })();
  true;
''';

/// WebView tab — native session/view correlation for Browser RUM in WebViews.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  String _nativeContext = 'Waiting for WebView context...';
  String? _nativeSessionId;
  String? _nativeViewId;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    // Mark the active view as a WebView before loading the page so the
    // native context (session.id + native.view.id) lands on the right span.
    await L9Rum.startView('WebViewSessionCorrelation');

    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _kChannelName,
        onMessageReceived: _handleMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // Re-inject native context on every page start so id rollovers
          // (session expiry, view changes) reach the page on the next load.
          onPageStarted: (_) async {
            try {
              final String script =
                  await L9Rum.getWebViewInjectedJavaScript();
              await controller.runJavaScript(script);
              await controller.runJavaScript(_browserRumBootstrap());
              addLog('WebView injected JS loaded (${script.length} chars)');
            } catch (e) {
              await L9Rum.captureError(e,
                  context: <String, dynamic>{'screen': 'WebViewCorrelation'});
              if (mounted) {
                setState(() => _nativeContext =
                    'Failed to load WebView injected JavaScript: $e');
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(kWebViewTestUrl));

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  void _handleMessage(JavaScriptMessage message) {
    try {
      final Map<String, dynamic> payload =
          jsonDecode(message.message) as Map<String, dynamic>;
      final Map<String, dynamic> context =
          (payload['context'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final String? sessionId = context['sessionId'] as String?;
      final String? viewId =
          (context['nativeViewId'] ?? context['viewId']) as String?;
      const JsonEncoder enc = JsonEncoder.withIndent('  ');
      setState(() {
        _nativeSessionId = sessionId;
        _nativeViewId = viewId;
        _nativeContext = enc.convert(payload);
      });
      addLog(
          'WebView context → session:${sessionId ?? "missing"} view:${viewId ?? "missing"}');
    } catch (_) {
      setState(() => _nativeContext = message.message);
    }
  }

  Future<void> _refresh() async {
    final WebViewController? c = _controller;
    if (c == null) return;
    await L9Rum.startView('WebViewSessionCorrelation');
    await c.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebView Correlation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const FeatureBadge(features: <String>[
            'getWebViewInjectedJavaScript() native context helper',
            'Loads a public WebView site that makes API requests',
            'Native session.id shared with Browser RUM in the page',
            'Native view.id stamped as native.view.id',
          ]),
          const Hint(
            'This screen loads the Last9 app in a real WebView. The app injects '
            'native context and boots Browser RUM on the page, so the page\'s '
            'API calls, web vitals, and JS errors share the native session.',
          ),
          PrimaryButton(label: 'Refresh WebView Context', onPressed: _refresh),
          const SectionTitle('Last Context Probe'),
          SummaryCard(
            title: 'Native WebView Context',
            selectable: true,
            lines: <String>[
              'sessionId: ${_nativeSessionId ?? 'waiting...'}',
              'native.view.id: ${_nativeViewId ?? 'waiting...'}',
            ],
          ),
          ContextCard(text: _nativeContext),
          const SectionTitle('Actual WebView'),
          Container(
            height: 360,
            margin: const EdgeInsets.only(bottom: 24),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: _controller == null
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator()))
                : WebViewWidget(controller: _controller!),
          ),
        ],
      ),
    );
  }
}
