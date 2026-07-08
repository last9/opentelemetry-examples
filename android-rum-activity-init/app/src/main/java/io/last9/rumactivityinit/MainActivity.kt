package io.last9.rumactivityinit

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.last9.rum.L9Rum
import io.last9.rum.L9RumConfig
import java.io.IOException
import java.util.concurrent.Executors
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class MainActivity : Activity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private lateinit var client: OkHttpClient

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        L9Rum.initialize(
            application,
            L9RumConfig(
                baseUrl = BuildConfig.LAST9_BASE_URL,
                clientToken = BuildConfig.LAST9_CLIENT_TOKEN,
                origin = BuildConfig.LAST9_ORIGIN,
                serviceName = "android-rum-activity-init",
                serviceVersion = BuildConfig.VERSION_NAME,
                deploymentEnvironment = "development",
                debugLogs = true,
            ),
        )

        client = L9Rum.instrumentOkHttp(OkHttpClient.Builder(), this).build()
        setContentView(buildUi())
        append("SDK initialized from MainActivity using activity.application")
    }

    override fun onDestroy() {
        executor.shutdownNow()
        L9Rum.shutdown()
        super.onDestroy()
    }

    private fun buildUi(): ScrollView {
        status = TextView(this).apply {
            textSize = 15f
            setPadding(32, 24, 32, 24)
        }

        val getButton = Button(this).apply {
            text = "GET todo"
            setOnClickListener { runRequest("GET", "https://jsonplaceholder.typicode.com/todos/1") }
        }
        val postButton = Button(this).apply {
            text = "POST event"
            setOnClickListener { runRequest("POST", "https://jsonplaceholder.typicode.com/posts") }
        }
        val httpBinButton = Button(this).apply {
            text = "GET httpbin"
            setOnClickListener { runRequest("GET", "https://httpbin.org/get") }
        }
        val flushButton = Button(this).apply {
            text = "Flush"
            setOnClickListener {
                L9Rum.flush()
                append("Flush requested")
            }
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 48, 32, 48)
            addView(title("Last9 RUM Activity Init"))
            addView(body("No custom Application subclass. The SDK is initialized from MainActivity with activity.application."))
            addView(getButton)
            addView(postButton)
            addView(httpBinButton)
            addView(flushButton)
            addView(status)
        }

        return ScrollView(this).apply {
            addView(content, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    private fun title(value: String): TextView = TextView(this).apply {
        text = value
        textSize = 24f
        setPadding(0, 0, 0, 16)
    }

    private fun body(value: String): TextView = TextView(this).apply {
        text = value
        textSize = 16f
        setPadding(0, 0, 0, 24)
    }

    private fun runRequest(method: String, url: String) {
        append("Starting $method $url")
        executor.execute {
            try {
                val requestBuilder = Request.Builder().url(url)
                if (method == "POST") {
                    val body = "{\"source\":\"android-rum-activity-init\"}".toRequestBody("application/json".toMediaType())
                    requestBuilder.post(body)
                }
                client.newCall(requestBuilder.build()).execute().use { response ->
                    append("$method ${response.request.url} -> HTTP ${response.code}")
                }
            } catch (error: IOException) {
                L9Rum.captureError(error, mapOf("example.operation" to method, "example.url" to url))
                append("$method $url failed: ${error.message}")
            }
        }
    }

    private fun append(message: String) {
        mainHandler.post {
            status.append("\n$message")
        }
    }
}
