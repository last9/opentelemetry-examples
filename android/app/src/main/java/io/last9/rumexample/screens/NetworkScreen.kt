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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.last9.rumexample.EventLog
import io.last9.rumexample.data.Api
import io.last9.rumexample.data.ApiResult
import io.last9.rumexample.data.DemoRequestTags
import io.last9.rumexample.data.Todo
import io.last9.rumexample.data.parseTodo
import io.last9.rumexample.data.parseTodos
import io.last9.rumexample.ui.ApiResultCard
import io.last9.rumexample.ui.FeatureBadge
import io.last9.rumexample.ui.Hint
import io.last9.rumexample.ui.L9Card
import io.last9.rumexample.ui.L9Theme
import io.last9.rumexample.ui.LoadingCard
import io.last9.rumexample.ui.PrimaryButton
import io.last9.rumexample.ui.ScreenHeader
import io.last9.rumexample.ui.SectionTitle
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch

private val PUBLIC_API_DEMOS = listOf(
    "todos limit" to "https://jsonplaceholder.typicode.com/todos?_limit=1",
    "comments by post" to "https://jsonplaceholder.typicode.com/comments?postId=1",
    "user detail" to "https://jsonplaceholder.typicode.com/users/1",
    "album detail" to "https://jsonplaceholder.typicode.com/albums/1",
    "GitHub zen" to "https://api.github.com/zen",
    "random dog image API" to "https://dog.ceo/api/breeds/image/random",
)

private val TRACKED_NETWORK_DEMOS = listOf(
    "tracked posts list" to "https://jsonplaceholder.typicode.com/posts?_limit=3",
    "tracked todo detail" to "https://jsonplaceholder.typicode.com/todos/2",
    "tracked GitHub rate limit" to "https://api.github.com/rate_limit",
)

/**
 * Network tab — todos CRUD plus public/tracked API demos, all via the
 * instrumented OkHttp client off the main thread. Mirrors the reference.
 */
@Composable
fun NetworkScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val todos = remember { mutableStateListOf<Todo>() }
    val results = remember { mutableStateListOf<ApiResult>() }
    var loading by remember { mutableStateOf(true) }
    var newTitle by remember { mutableStateOf("") }
    var publicApiLoading by remember { mutableStateOf(false) }
    var trackedLoading by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        loading = true
        val r = Api.request(context, "GET", "/todos?_limit=10", tags = DemoRequestTags("network", "todos-list"))
        todos.clear(); todos.addAll(parseTodos(r.body ?: "[]"))
        results.add(0, r)
        EventLog.add("GET /todos → ${r.status} (${r.durationMs}ms)")
        loading = false
    }

    fun createTodo() {
        val title = newTitle.trim()
        if (title.isEmpty()) return
        scope.launch {
            val body = """{"title":"$title","completed":false,"userId":1}"""
            val r = Api.request(context, "POST", "/todos", body, DemoRequestTags("network", "todo-create"))
            results.add(0, r)
            EventLog.add("POST /todos → ${r.status} (${r.durationMs}ms)")
            parseTodo(r.body ?: "{}")?.let { todos.add(0, it.copy(title = title)) }
            newTitle = ""
        }
    }

    fun toggleTodo(todo: Todo) {
        scope.launch {
            val body = """{"completed":${!todo.completed}}"""
            val r = Api.request(context, "PATCH", "/todos/${todo.id}", body, DemoRequestTags("network", "todo-toggle"))
            results.add(0, r)
            EventLog.add("PATCH /todos/${todo.id} → ${r.status} (${r.durationMs}ms)")
            val idx = todos.indexOfFirst { it.id == todo.id }
            if (idx >= 0) todos[idx] = todos[idx].copy(completed = !todo.completed)
        }
    }

    fun deleteTodo(todo: Todo) {
        scope.launch {
            val r = Api.request(context, "DELETE", "/todos/${todo.id}", tags = DemoRequestTags("network", "todo-delete"))
            results.add(0, r)
            EventLog.add("DELETE /todos/${todo.id} → ${r.status} (${r.durationMs}ms)")
            todos.removeAll { it.id == todo.id }
        }
    }

    fun runDemos(
        demos: List<Pair<String, String>>,
        labelPrefix: String,
        namePrefix: String,
        setLoading: (Boolean) -> Unit,
        logKind: String,
    ) {
        setLoading(true)
        scope.launch {
            val demoResults = runParallelDemos(context, demos, labelPrefix, namePrefix)
            results.addAll(0, demoResults)
            EventLog.add("$logKind → ${demoResults.size} captured requests")
            setLoading(false)
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(L9Theme.ScreenBg)) {
        ScreenHeader("Todos")
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FeatureBadge(
                features = listOf(
                    "GET /todos (list)",
                    "POST /todos (create)",
                    "PATCH /todos/:id (toggle)",
                    "DELETE /todos/:id (remove)",
                    "public API demos visible in the dashboard",
                    "ignorePatterns only suppress image/CDN resources",
                    "Network APIs include l9_demo_tab=network query tags",
                ),
            )

            // Add todo
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = newTitle,
                    onValueChange = { newTitle = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("New todo...", color = L9Theme.HintText) },
                    singleLine = true,
                    shape = RoundedCornerShape(8.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = L9Theme.Accent,
                        unfocusedBorderColor = L9Theme.CardBorder,
                    ),
                    keyboardActions = KeyboardActions(onDone = { createTodo() }),
                )
                PrimaryButton(label = "Add", onClick = { createTodo() })
            }

            // Todo list
            if (loading) {
                LoadingCard()
            } else {
                todos.forEach { todo ->
                    L9Card {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                if (todo.completed) "✅" else "⬜",
                                fontSize = 18.sp,
                                modifier = Modifier
                                    .clickable { toggleTodo(todo) }
                                    .padding(end = 10.dp),
                            )
                            Text(
                                todo.title,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (todo.completed) L9Theme.HintText else L9Theme.TitleText,
                                textDecoration = if (todo.completed) TextDecoration.LineThrough else TextDecoration.None,
                                maxLines = 2,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                "✕",
                                fontSize = 16.sp,
                                color = L9Theme.Error,
                                modifier = Modifier
                                    .clickable { deleteTodo(todo) }
                                    .padding(start = 10.dp),
                            )
                        }
                    }
                }
            }

            SectionTitle("Public API Requests")
            Hint("Sends public API requests across JSONPlaceholder, GitHub, and dog.ceo. These no longer match ignorePatterns, so they should create network spans and appear in the Last9 dashboard. Image/CDN patterns are still ignored. Filter by l9_demo_tab=network.")
            PrimaryButton(
                label = if (publicApiLoading) "Sending public API requests..." else "Run Public API Demo",
                enabled = !publicApiLoading,
                onClick = {
                    runDemos(PUBLIC_API_DEMOS, "PUBLIC API ", "public-", { publicApiLoading = it }, "public API demo")
                },
                modifier = Modifier.fillMaxWidth(),
            )

            SectionTitle("Tracked Network Requests")
            Hint("Sends requests that do not match ignorePatterns, so these should create network spans and appear in the Last9 dashboard. Filter by l9_demo_tab=network or l9_demo_request.")
            PrimaryButton(
                label = if (trackedLoading) "Sending tracked requests..." else "Run Tracked Requests Demo",
                enabled = !trackedLoading,
                onClick = {
                    runDemos(TRACKED_NETWORK_DEMOS, "TRACKED ", "", { trackedLoading = it }, "tracked demo")
                },
                modifier = Modifier.fillMaxWidth(),
            )

            if (results.isNotEmpty()) {
                SectionTitle("API Log")
                results.take(10).forEach { r ->
                    ApiResultCard(r.label, r.status, r.ok, r.durationMs, r.error)
                }
            }
            Spacer(Modifier.size(8.dp))
        }
    }
}

private suspend fun runParallelDemos(
    context: android.content.Context,
    demos: List<Pair<String, String>>,
    labelPrefix: String,
    namePrefix: String,
): List<ApiResult> = kotlinx.coroutines.coroutineScope {
    demos.map { (label, url) ->
        async {
            val name = namePrefix + label.replace(Regex("\\s+"), "-").lowercase()
            Api.timedGet(context, "$labelPrefix$label", url, DemoRequestTags("network", name)).second
        }
    }.awaitAll()
}
