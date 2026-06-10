package io.last9.rumexample.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import io.last9.rum.L9Rum
import io.last9.rumexample.EventLog
import io.last9.rumexample.data.Api
import io.last9.rumexample.data.ApiResult
import io.last9.rumexample.data.Comment
import io.last9.rumexample.data.DemoRequestTags
import io.last9.rumexample.data.Post
import io.last9.rumexample.data.User
import io.last9.rumexample.data.parseComments
import io.last9.rumexample.data.parsePost
import io.last9.rumexample.data.parsePosts
import io.last9.rumexample.data.parseUsers
import io.last9.rumexample.ui.AccentEntryCard
import io.last9.rumexample.ui.ApiResultCard
import io.last9.rumexample.ui.FeatureBadge
import io.last9.rumexample.ui.Hint
import io.last9.rumexample.ui.L9Theme
import io.last9.rumexample.ui.LoadingCard
import io.last9.rumexample.ui.PostListItem
import io.last9.rumexample.ui.ScreenHeader
import io.last9.rumexample.ui.SectionTitle
import io.last9.rumexample.ui.SummaryCard

private object HomeRoutes {
    const val DASHBOARD = "dashboard"
    const val DETAIL = "detail/{postId}"
    fun detail(postId: Int) = "detail/$postId"
}

/**
 * Home tab — a nested navigation stack (Dashboard → Detail) using real Compose
 * navigation routes, mirroring the reference app's Home stack.
 */
@Composable
fun HomeScreen() {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = HomeRoutes.DASHBOARD) {
        composable(HomeRoutes.DASHBOARD) {
            DashboardScreen(onOpenPost = { postId ->
                L9Rum.addEvent("nav_tap", mapOf("destination" to "Post #$postId"))
                EventLog.add("nav → Post #$postId")
                nav.navigate(HomeRoutes.detail(postId))
            })
        }
        composable(
            HomeRoutes.DETAIL,
            arguments = listOf(navArgument("postId") { type = NavType.IntType }),
        ) { entry ->
            val postId = entry.arguments?.getInt("postId") ?: 1
            DetailScreen(postId = postId, onBack = { nav.popBackStack() })
        }
    }
}

@Composable
private fun DashboardScreen(onOpenPost: (Int) -> Unit) {
    val context = LocalContext.current
    val posts = remember { mutableStateListOf<Post>() }
    val users = remember { mutableStateListOf<User>() }
    val comments = remember { mutableStateListOf<Comment>() }
    val homeRequests = remember { mutableStateListOf<ApiResult>() }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        loading = true
        L9Rum.startView("Home")
        EventLog.add("startView: Home")
        // Five requests in parallel (instrumented OkHttp), off the main thread.
        val postsRes = Api.timedGet(context, "Home fast posts", "https://jsonplaceholder.typicode.com/posts?_limit=20", DemoRequestTags("home", "posts-list"))
        val usersRes = Api.timedGet(context, "Home fast users", "https://jsonplaceholder.typicode.com/users?_limit=5", DemoRequestTags("home", "users-list"))
        val commentsRes = Api.timedGet(context, "Home fast comments", "https://jsonplaceholder.typicode.com/comments?postId=1", DemoRequestTags("home", "comments-for-post"))
        val delayOneRes = Api.timedGet(context, "Home delayed 1s", "https://httpbin.org/delay/1", DemoRequestTags("home", "delay-1s"))
        val delayThreeRes = Api.timedGet(context, "Home delayed 3s", "https://httpbin.org/delay/3", DemoRequestTags("home", "delay-3s"))

        val requestResults = listOf(
            postsRes.second, usersRes.second, commentsRes.second,
            delayOneRes.second, delayThreeRes.second,
        )
        posts.clear(); posts.addAll(parsePosts(postsRes.first))
        users.clear(); users.addAll(parseUsers(usersRes.first))
        comments.clear(); comments.addAll(parseComments(commentsRes.first))
        homeRequests.clear(); homeRequests.addAll(requestResults)
        val maxResult = requestResults.maxByOrNull { it.durationMs }
        EventLog.add("Home APIs complete; expected max view.ttfd source: ${maxResult?.label} (${maxResult?.durationMs}ms)")
        loading = false
    }

    Column(modifier = Modifier.fillMaxSize().background(L9Theme.ScreenBg)) {
        ScreenHeader("Posts")
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (loading) {
                LoadingCard("Loading posts, users, and comments before the Home screen is fully displayed.")
            } else {
                FeatureBadge(
                    features = listOf(
                        "Home starts an active View before API requests",
                        "Fast and delayed GET requests run before full content render",
                        "SDK sets view.ttfd from the maximum request time on this view",
                        "Home APIs include l9_demo_tab=home query tags",
                    ),
                )
                SummaryCard(
                    title = "Home full display data",
                    lines = listOf(
                        "${posts.size} posts",
                        "${users.size} users",
                        "${comments.size} comments for the featured post",
                    ),
                )
                SectionTitle("TTFD Request Timings")
                Hint("The delayed 3s request should usually be the max-duration source for view.ttfd. Filter dashboard URLs by l9_demo_tab=home or l9_demo_request=delay-3s.")
                homeRequests.forEach { r ->
                    ApiResultCard(r.label, r.status, r.ok, r.durationMs, r.error)
                }
                posts.forEach { post ->
                    PostListItem(post.title, post.body, onClick = { onOpenPost(post.id) })
                }
                SectionTitle("Featured Users")
                users.forEach { u ->
                    AccentEntryCard(accent = L9Theme.Accent, label = u.name, sub = u.email)
                }
                SectionTitle("Featured Comments")
                comments.take(3).forEach { c ->
                    AccentEntryCard(accent = L9Theme.Ok, label = c.name, body = c.body)
                }
            }
            Spacer(Modifier.size(8.dp))
        }
    }
}

@Composable
private fun DetailScreen(postId: Int, onBack: () -> Unit) {
    val context = LocalContext.current
    var post by remember { mutableStateOf<Post?>(null) }
    val comments = remember { mutableStateListOf<Comment>() }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(postId) {
        loading = true
        val postRes = Api.timedGet(context, "detail-post", "https://jsonplaceholder.typicode.com/posts/$postId", DemoRequestTags("home", "detail-post"))
        val commentsRes = Api.timedGet(context, "detail-comments", "https://jsonplaceholder.typicode.com/posts/$postId/comments", DemoRequestTags("home", "detail-comments"))
        post = parsePost(postRes.first)
        val parsed = parseComments(commentsRes.first)
        comments.clear(); comments.addAll(parsed)
        loading = false
        EventLog.add("GET /posts/$postId → ${postRes.second.status}")
        EventLog.add("GET /posts/$postId/comments → ${commentsRes.second.status} (${parsed.size})")
    }

    Column(modifier = Modifier.fillMaxSize().background(L9Theme.ScreenBg)) {
        ScreenHeader("Post #$postId", onBack = onBack)
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (loading) {
                LoadingCard()
            } else {
                SectionTitle(post?.title ?: "")
                Hint(post?.body ?: "")
                SectionTitle("Comments (${comments.size})")
                comments.forEach { c ->
                    AccentEntryCard(accent = L9Theme.Accent, label = c.name, sub = c.email, body = c.body)
                }
            }
            Spacer(Modifier.size(8.dp))
        }
    }
}
