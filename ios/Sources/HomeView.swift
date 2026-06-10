import SwiftUI
import Last9RUM

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Home Tab — NavigationStack with Dashboard + Detail.
//  Features: app startup, view transitions, parallel network requests, TTFD.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Wraps the Dashboard in a `NavigationStack` so tapping a post pushes a real
/// Detail route (the SDK records a view transition on each navigation).
struct HomeTab: View {
    var body: some View {
        NavigationStack {
            DashboardScreen()
                .navigationDestination(for: Int.self) { postId in
                    DetailScreen(postId: postId)
                }
        }
    }
}

struct DashboardScreen: View {
    @State private var posts: [Post] = []
    @State private var users: [User] = []
    @State private var comments: [Comment] = []
    @State private var homeRequests: [ApiResult] = []
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            if loading {
                VStack(spacing: 12) {
                    ProgressView().padding(.top, 8)
                    Hint("Loading posts, users, and comments before the Home screen is fully displayed.")
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .cardStyle()
            } else {
                FeatureBadge(features: [
                    "Home starts an active View before API requests",
                    "Fast and delayed GET requests run before full content render",
                    "SDK sets view.ttfd from the maximum request time on this view",
                    "Home APIs include l9_demo_tab=home query tags",
                ])

                // Summary card.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Home full display data")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(posts.count) posts").summaryText()
                    Text("\(users.count) users").summaryText()
                    Text("\(comments.count) comments for the featured post").summaryText()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                SectionHeader(title: "TTFD Request Timings")
                Hint("The delayed 3s request should usually be the max-duration source for view.ttfd. Filter dashboard URLs by l9_demo_tab=home or l9_demo_request=delay-3s.")
                ForEach(homeRequests) { result in
                    ApiResultCard(label: result.label, status: result.status,
                                  durationMs: result.durationMs, ok: result.ok,
                                  detail: result.error ?? result.body)
                }

                // Posts list — tapping pushes Detail.
                VStack(spacing: 8) {
                    ForEach(posts) { post in
                        NavigationLink(value: post.id) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(post.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Text(post.body)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("›").font(.system(size: 20)).foregroundStyle(Color(.systemGray3))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .cardStyle(cornerRadius: 10)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            L9Rum.shared.addEvent("nav_tap", attributes: ["destination": "Post #\(post.id)"])
                            EventLog.shared.add("nav → Post #\(post.id)")
                        })
                    }
                }

                SectionHeader(title: "Featured Users")
                ForEach(users) { user in
                    leftBarCard(color: Theme.accent) {
                        Text(user.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(user.email).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                }

                SectionHeader(title: "Featured Comments")
                ForEach(comments.prefix(3)) { comment in
                    leftBarCard(color: Theme.ok) {
                        Text(comment.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(comment.body).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Posts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHomeData() }
    }

    @ViewBuilder
    private func leftBarCard<C: View>(color: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .cardStyle(cornerRadius: 8)
    }

    private func loadHomeData() async {
        guard loading else { return }
        L9Rum.shared.startView("Home")
        EventLog.shared.add("startView: Home")

        async let postsRes = ApiClient.timedJson("Home fast posts", "\(API_BASE)/posts?_limit=20",
                                                  tags: .init(tab: .home, name: "posts-list"), as: [Post].self)
        async let usersRes = ApiClient.timedJson("Home fast users", "\(API_BASE)/users?_limit=5",
                                                 tags: .init(tab: .home, name: "users-list"), as: [User].self)
        async let commentsRes = ApiClient.timedJson("Home fast comments", "\(API_BASE)/comments?postId=1",
                                                    tags: .init(tab: .home, name: "comments-for-post"), as: [Comment].self)
        async let delayOneRes = ApiClient.timedGet(label: "Home delayed 1s", url: "https://httpbin.org/delay/1",
                                                   tags: .init(tab: .home, name: "delay-1s"))
        async let delayThreeRes = ApiClient.timedGet(label: "Home delayed 3s", url: "https://httpbin.org/delay/3",
                                                     tags: .init(tab: .home, name: "delay-3s"))

        let p = await postsRes, u = await usersRes, c = await commentsRes
        let d1 = await delayOneRes, d3 = await delayThreeRes
        let requestResults = [p.result, u.result, c.result, d1, d3]
        let maxResult = requestResults.max(by: { $0.durationMs < $1.durationMs })

        posts = p.data ?? []
        users = u.data ?? []
        comments = c.data ?? []
        homeRequests = requestResults
        loading = false
        if let maxResult {
            EventLog.shared.add("Home APIs complete; expected max view.ttfd source: \(maxResult.label) (\(maxResult.durationMs)ms)")
        }
    }
}

struct DetailScreen: View {
    let postId: Int

    @State private var post: Post?
    @State private var comments: [Comment] = []
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else {
                SectionHeader(title: post?.title ?? "Post #\(postId)")
                Hint(post?.body ?? "")
                SectionHeader(title: "Comments (\(comments.count))")
                ForEach(comments) { c in
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.accent).frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            Text(c.email).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            Text(c.body).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .cardStyle(cornerRadius: 8)
                }
            }
        }
        .navigationTitle("Post #\(postId)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let postTags = DemoRequestTags(tab: .home, name: "detail-post")
        let commentsTags = DemoRequestTags(tab: .home, name: "detail-comments")
        async let postRes = ApiClient.timedJson("detail post", "\(API_BASE)/posts/\(postId)",
                                                tags: postTags, as: Post.self)
        async let commentsRes = ApiClient.timedJson("detail comments", "\(API_BASE)/posts/\(postId)/comments",
                                                    tags: commentsTags, as: [Comment].self)
        let p = await postRes, c = await commentsRes
        post = p.data
        comments = c.data ?? []
        loading = false
        EventLog.shared.add("GET /posts/\(postId) → \(p.result.status)")
        EventLog.shared.add("GET /posts/\(postId)/comments → \(c.result.status) (\(comments.count))")
    }
}

private extension Text {
    func summaryText() -> some View {
        self.font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
    }
}
