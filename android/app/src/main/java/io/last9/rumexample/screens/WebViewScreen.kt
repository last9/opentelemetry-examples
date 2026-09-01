package io.last9.rumexample.screens

import android.annotation.SuppressLint
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.last9.rum.L9Rum
import io.last9.rumexample.EventLog
import io.last9.rumexample.RumConfigInfo
import io.last9.rumexample.ui.ContextCard
import io.last9.rumexample.ui.FeatureBadge
import io.last9.rumexample.ui.Hint
import io.last9.rumexample.ui.L9Theme
import io.last9.rumexample.ui.PrimaryButton
import io.last9.rumexample.ui.ScreenHeader
import io.last9.rumexample.ui.SectionTitle
import io.last9.rumexample.ui.SummaryCard
import org.json.JSONObject

private const val HARNESS_URL = "file:///android_asset/webview_harness.html"
private const val LIVE_URL = "https://app.last9.io/"
private const val BROWSER_RUM_SDK_URL = "https://cdn.last9.io/rum-sdk/builds/2.5.0-alpha/l9.umd.js"

private fun webViewRumBootstrap(baseUrl: String, clientToken: String): String = """
  (function() {
    if (window.__L9_WEBVIEW_RUM_BOOTSTRAPPED) return true;
    window.__L9_WEBVIEW_RUM_BOOTSTRAPPED = true;

    function postContext(reason) {
      try {
        window.L9RumNative && window.L9RumNative.postMessage(JSON.stringify({
          reason: reason,
          href: window.location.href,
          hasL9RUM: !!window.L9RUM,
          context: window.__LAST9_RUM_NATIVE_CONTEXT || null
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
          baseUrl: ${JSONObject.quote(baseUrl)},
          headers: { clientToken: ${JSONObject.quote(clientToken)} },
          resourceAttributes: {
            serviceName: ${JSONObject.quote(RumConfigInfo.SERVICE_NAME)},
            deploymentEnvironment: ${JSONObject.quote(RumConfigInfo.ENVIRONMENT)},
            appVersion: ${JSONObject.quote(RumConfigInfo.SERVICE_VERSION)}
          },
          sampleRate: 100,
          debug: true,
          debugLogs: true
        });
        window.L9RUM.addEvent('webview_real_page_loaded', { source: 'android-webview-demo' });
        postContext('browser-rum-init');
      } catch (e) {
        postContext('browser-rum-init-error:' + (e && e.message ? e.message : e));
      }
    }

    function loadBrowserRum() {
      if (window.L9RUM) { initBrowserRum(); return; }
      var script = document.createElement('script');
      script.src = ${JSONObject.quote(BROWSER_RUM_SDK_URL)};
      script.async = true;
      script.onload = initBrowserRum;
      script.onerror = function () { postContext('browser-rum-load-error'); };
      (document.head || document.documentElement).appendChild(script);
    }

    window.addEventListener('l9rum:native_context', function () { postContext('l9rum:native_context'); });
    loadBrowserRum();
    setTimeout(function () { postContext('initial-page-load'); }, 500);
  })();
  true;
""".trimIndent()

/**
 * WebView harness for ENG-1844 / 1837 / 1847 / 1848.
 *
 * Cases: path rotation, query-only, hash/pushState SPA, leave+return fold,
 * flush without session rollover, kill/restart tombstone + restore.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun WebViewScreen() {
    var nativeContext by remember { mutableStateOf("Waiting for WebView context...") }
    var nativeSessionId by remember { mutableStateOf<String?>(null) }
    var nativeViewId by remember { mutableStateOf<String?>(null) }
    var webViewKey by remember { mutableIntStateOf(0) }
    var targetUrl by remember { mutableStateOf(HARNESS_URL) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    val lastReloadedKey = remember { intArrayOf(0) }

    LaunchedEffect(Unit) {
        L9Rum.startView("WebViewHarness")
        EventLog.add("startView: WebViewHarness")
    }

    DisposableEffect(Unit) {
        onDispose {
            EventLog.add("WebViewScreen disposed (leave tab → resume rebind on return)")
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(L9Theme.ScreenBg)) {
        ScreenHeader("WebView Harness")
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FeatureBadge(
                features = listOf(
                    "Local 1.6.9 SDK (path rotate / resume fold / SPA / kill tombstone)",
                    "instrument(webView) + getWebViewInjectedJavaScript()",
                    "Harness HTML: path, query, hash, pushState",
                    "flush() without session rollover",
                ),
            )
            Hint(
                "1) Stay on harness → tap path buttons → expect new view.url rows.\n" +
                    "2) Switch Home → WebView → expect fold onto one view (no bare Activity).\n" +
                    "3) Tap Flush, then force-stop from Recents → cold start → prior page via " +
                    "process_death view tombstone; restored page gets a new view.",
            )

            SectionTitle("Load target")
            PrimaryButton(
                label = "Load harness HTML (SPA / path)",
                onClick = {
                    targetUrl = HARNESS_URL
                    webViewKey += 1
                    EventLog.add("load harness HTML")
                },
                modifier = Modifier.fillMaxWidth(),
            )
            PrimaryButton(
                label = "Load app.last9.io (live)",
                onClick = {
                    targetUrl = LIVE_URL
                    webViewKey += 1
                    EventLog.add("load live URL")
                },
                modifier = Modifier.fillMaxWidth(),
            )

            SectionTitle("Native actions")
            PrimaryButton(
                label = "flush() — export, keep session",
                onClick = {
                    L9Rum.flush()
                    EventLog.add("L9Rum.flush()")
                },
                modifier = Modifier.fillMaxWidth(),
            )
            PrimaryButton(
                label = "addEvent(WebView_shown)",
                onClick = {
                    L9Rum.addEvent("WebView_shown", mapOf("source" to "android-harness"))
                    EventLog.add("addEvent WebView_shown")
                },
                modifier = Modifier.fillMaxWidth(),
            )
            PrimaryButton(
                label = "Reload WebView (same URL)",
                onClick = {
                    webViewRef?.reload()
                    EventLog.add("webview.reload()")
                },
                modifier = Modifier.fillMaxWidth(),
            )
            PrimaryButton(
                label = "Crash process (uncaught) — optional",
                onClick = {
                    EventLog.add("throwing for crash-path end+flush")
                    throw RuntimeException("intentional harness crash for ENG-1847")
                },
                modifier = Modifier.fillMaxWidth(),
            )

            SectionTitle("Last Context Probe")
            SummaryCard(
                title = "Native WebView Context",
                lines = listOf(
                    "sessionId: ${nativeSessionId ?: "waiting..."}",
                    "native.view.id: ${nativeViewId ?: "waiting..."}",
                    "url: $targetUrl",
                ),
            )
            ContextCard(nativeContext)

            SectionTitle("Actual WebView")
            AndroidView(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(420.dp)
                    .clip(RoundedCornerShape(12.dp)),
                factory = { ctx ->
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.allowFileAccess = true
                        L9Rum.instrument(this)
                        addJavascriptInterface(
                            object {
                                @JavascriptInterface
                                fun postMessage(data: String) {
                                    post {
                                        runCatching {
                                            val payload = JSONObject(data)
                                            val ctxObj = payload.optJSONObject("context")
                                            val session = ctxObj?.optString("sessionId").orEmptyOrNull()
                                            val view = (ctxObj?.optString("nativeViewId").orEmptyOrNull())
                                                ?: ctxObj?.optString("viewId").orEmptyOrNull()
                                            nativeSessionId = session
                                            nativeViewId = view
                                            nativeContext = payload.toString(2)
                                            EventLog.add(
                                                "WebView context → session:${session ?: "missing"} " +
                                                    "view:${view ?: "missing"} href:${payload.optString("href")}",
                                            )
                                        }.onFailure { nativeContext = data }
                                    }
                                }
                            },
                            "L9RumNative",
                        )
                        webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView, url: String) {
                                EventLog.add("onPageFinished $url")
                                val script = L9Rum.getWebViewInjectedJavaScript()
                                view.evaluateJavascript(script, null)
                                if (!url.startsWith("file:")) {
                                    view.evaluateJavascript(
                                        webViewRumBootstrap(
                                            io.last9.rumexample.BuildConfig.LAST9_BASE_URL,
                                            io.last9.rumexample.BuildConfig.LAST9_CLIENT_TOKEN,
                                        ),
                                        null,
                                    )
                                }
                            }
                        }
                        webViewRef = this
                        loadUrl(targetUrl)
                    }
                },
                update = { webView ->
                    webViewRef = webView
                    if (lastReloadedKey[0] != webViewKey) {
                        lastReloadedKey[0] = webViewKey
                        L9Rum.instrument(webView)
                        webView.loadUrl(targetUrl)
                    }
                },
            )
            Spacer(Modifier.size(16.dp))
        }
    }
}

private fun String?.orEmptyOrNull(): String? = if (isNullOrEmpty()) null else this
