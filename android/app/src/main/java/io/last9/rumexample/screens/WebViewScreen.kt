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

private const val WEBVIEW_TEST_URL = "https://app.last9.io/"
private const val BROWSER_RUM_SDK_URL = "https://cdn.last9.io/rum-sdk/builds/2.5.0-alpha/l9.umd.js"

/**
 * Browser-RUM bootstrap injected after [L9Rum.getWebViewInjectedJavaScript]. It
 * loads the Browser RUM SDK from the CDN, inits it against this app's baseUrl +
 * clientToken (read from window.__LAST9_RUM_NATIVE_CONTEXT set by the native
 * helper), and posts the native context back to the app via the
 * `L9RumNative.postMessage` bridge so the context-probe card can render it.
 * Analogous to the reference's WEBVIEW_RUM_BOOTSTRAP.
 */
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
 * WebView tab — loads a real WebView, calls [L9Rum.getWebViewInjectedJavaScript]
 * and [L9Rum.instrument] so the page's Browser RUM shares the native session.id
 * and native.view.id, and shows the resulting context probe.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun WebViewScreen() {
    var nativeContext by remember { mutableStateOf("Waiting for WebView context...") }
    var nativeSessionId by remember { mutableStateOf<String?>(null) }
    var nativeViewId by remember { mutableStateOf<String?>(null) }
    var webViewKey by remember { mutableIntStateOf(0) }
    val lastReloadedKey = remember { intArrayOf(0) }

    LaunchedEffect(Unit) {
        L9Rum.startView("WebViewSessionCorrelation")
        EventLog.add("startView: WebViewSessionCorrelation")
    }

    Column(modifier = Modifier.fillMaxSize().background(L9Theme.ScreenBg)) {
        ScreenHeader("WebView Correlation")
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FeatureBadge(
                features = listOf(
                    "getWebViewInjectedJavaScript() native context helper",
                    "instrument(webView) re-injects on navigation",
                    "Native session.id shared with Browser RUM in the page",
                    "Native view.id stamped as native.view.id",
                ),
            )
            Hint("This screen loads the Last9 dashboard in a real WebView. The app injects native context and boots Browser RUM on the page so its spans share the native session.")

            PrimaryButton(
                label = "Refresh WebView Context",
                onClick = {
                    L9Rum.startView("WebViewSessionCorrelation")
                    EventLog.add("WebView context refresh")
                    webViewKey += 1
                },
                modifier = Modifier.fillMaxWidth(),
            )

            SectionTitle("Last Context Probe")
            SummaryCard(
                title = "Native WebView Context",
                lines = listOf(
                    "sessionId: ${nativeSessionId ?: "waiting..."}",
                    "native.view.id: ${nativeViewId ?: "waiting..."}",
                ),
            )
            ContextCard(nativeContext)

            SectionTitle("Actual WebView")
            AndroidView(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(360.dp)
                    .clip(RoundedCornerShape(12.dp)),
                factory = { ctx ->
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        // Correlate this WebView with the native session/view.
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
                                            EventLog.add("WebView context → session:${session ?: "missing"} view:${view ?: "missing"}")
                                        }.onFailure { nativeContext = data }
                                    }
                                }
                            },
                            "L9RumNative",
                        )
                        webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView, url: String) {
                                // Native context script + Browser-RUM bootstrap.
                                val script = L9Rum.getWebViewInjectedJavaScript()
                                EventLog.add("WebView injected JS loaded (${script.length} chars)")
                                view.evaluateJavascript(script, null)
                                view.evaluateJavascript(
                                    webViewRumBootstrap(
                                        io.last9.rumexample.BuildConfig.LAST9_BASE_URL,
                                        io.last9.rumexample.BuildConfig.LAST9_CLIENT_TOKEN,
                                    ),
                                    null,
                                )
                            }
                        }
                        loadUrl(WEBVIEW_TEST_URL)
                    }
                },
                update = { webView ->
                    // The refresh button bumps webViewKey; reload once per bump.
                    if (lastReloadedKey[0] != webViewKey) {
                        lastReloadedKey[0] = webViewKey
                        if (webViewKey > 0) webView.reload()
                    }
                },
            )
            Spacer(Modifier.size(16.dp))
        }
    }
}

private fun String?.orEmptyOrNull(): String? = if (isNullOrEmpty()) null else this
