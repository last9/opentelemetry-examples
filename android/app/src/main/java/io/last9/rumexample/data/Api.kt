package io.last9.rumexample.data

import android.content.Context
import io.last9.rum.L9Rum
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** JSONPlaceholder mock API — https://jsonplaceholder.typicode.com/guide/ */
const val API_BASE = "https://jsonplaceholder.typicode.com"

private val JSON_MEDIA = "application/json; charset=UTF-8".toMediaType()

/**
 * Result of a single instrumented HTTP request — mirrors the reference
 * `ApiResult` shape so [io.last9.rumexample.ui.ApiResultCard] can render it.
 */
data class ApiResult(
    val label: String,
    val method: String,
    val path: String,
    val status: Int,
    val ok: Boolean,
    val durationMs: Long,
    val error: String? = null,
    val body: String? = null,
)

/** Tags appended as query params + headers, mirroring the reference's demo tags. */
data class DemoRequestTags(val tab: String, val name: String)

/**
 * Single shared OkHttp client instrumented with the Last9 RUM SDK so every
 * request emits a parent HTTP span plus DNS/TCP/TLS/TTFB phase child spans,
 * with W3C traceparent + baggage headers attached automatically.
 */
object Api {
    @Volatile private var client: OkHttpClient? = null

    fun client(context: Context): OkHttpClient =
        client ?: synchronized(this) {
            client ?: L9Rum.instrumentOkHttp(OkHttpClient.Builder(), context.applicationContext)
                .build()
                .also { client = it }
        }

    /** Adds l9_demo / l9_demo_tab / l9_demo_request query params to a URL. */
    fun demoUrl(rawUrl: String, tags: DemoRequestTags): String =
        rawUrl.toHttpUrl().newBuilder()
            .addQueryParameter("l9_demo", "true")
            .addQueryParameter("l9_demo_tab", tags.tab)
            .addQueryParameter("l9_demo_request", tags.name)
            .build()
            .toString()

    private fun Request.Builder.demoHeaders(tags: DemoRequestTags): Request.Builder = apply {
        header("X-L9-Demo", "true")
        header("X-L9-Demo-Tab", tags.tab)
        header("X-L9-Demo-Request", tags.name)
    }

    /**
     * Performs an HTTP request against the JSONPlaceholder base URL off the main
     * thread, returning a timed [ApiResult]. Mirrors the reference `api()`.
     */
    suspend fun request(
        context: Context,
        method: String,
        path: String,
        jsonBody: String? = null,
        tags: DemoRequestTags = DemoRequestTags("network", "$method $path"),
    ): ApiResult = withContext(Dispatchers.IO) {
        val url = demoUrl("$API_BASE$path", tags)
        val start = System.currentTimeMillis()
        val builder = Request.Builder().url(url).demoHeaders(tags)
        when (method.uppercase()) {
            "GET" -> builder.get()
            "POST" -> builder.post((jsonBody ?: "{}").toRequestBody(JSON_MEDIA))
            "PATCH" -> builder.patch((jsonBody ?: "{}").toRequestBody(JSON_MEDIA))
            "PUT" -> builder.put((jsonBody ?: "{}").toRequestBody(JSON_MEDIA))
            "DELETE" -> builder.delete()
            else -> builder.method(method, jsonBody?.toRequestBody(JSON_MEDIA))
        }
        try {
            client(context).newCall(builder.build()).execute().use { resp ->
                val text = runCatching { resp.body?.string().orEmpty() }.getOrDefault("")
                ApiResult(
                    label = "$method $path",
                    method = method,
                    path = path,
                    status = resp.code,
                    ok = resp.isSuccessful,
                    durationMs = System.currentTimeMillis() - start,
                    error = null,
                    body = text.take(500),
                )
            }
        } catch (e: Exception) {
            ApiResult(
                label = "$method $path",
                method = method,
                path = path,
                status = 0,
                ok = false,
                durationMs = System.currentTimeMillis() - start,
                error = e.message,
                body = null,
            )
        }
    }

    /**
     * GETs an arbitrary (possibly absolute) URL off the main thread, returning
     * both the response body text and a timed [ApiResult]. Mirrors `timedJson()`.
     */
    suspend fun timedGet(
        context: Context,
        label: String,
        rawUrl: String,
        tags: DemoRequestTags,
    ): Pair<String, ApiResult> = withContext(Dispatchers.IO) {
        val url = demoUrl(rawUrl, tags)
        val start = System.currentTimeMillis()
        val request = Request.Builder().url(url).demoHeaders(tags).get().build()
        try {
            client(context).newCall(request).execute().use { resp ->
                val text = runCatching { resp.body?.string().orEmpty() }.getOrDefault("")
                text to ApiResult(
                    label = label,
                    method = "GET",
                    path = url,
                    status = resp.code,
                    ok = resp.isSuccessful,
                    durationMs = System.currentTimeMillis() - start,
                    error = null,
                    body = text.take(500),
                )
            }
        } catch (e: Exception) {
            "" to ApiResult(
                label = label,
                method = "GET",
                path = url,
                status = 0,
                ok = false,
                durationMs = System.currentTimeMillis() - start,
                error = e.message,
                body = null,
            )
        }
    }
}
