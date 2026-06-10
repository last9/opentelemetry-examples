import SwiftUI
import Last9RUM

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Network Tab — todos CRUD + public/tracked demos.
//  Features: network instrumentation, W3C trace context, baggage, correlation.
//  Every call goes through URLSession (auto-instrumented by the SDK).
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct NetworkView: View {
    @State private var todos: [Todo] = []
    @State private var results: [ApiResult] = []
    @State private var newTitle = ""
    @State private var loading = true
    @State private var publicApiLoading = false
    @State private var trackedLoading = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                FeatureBadge(features: [
                    "GET /todos (list)",
                    "POST /todos (create)",
                    "PATCH /todos/:id (toggle)",
                    "DELETE /todos/:id (remove)",
                    "public API demos visible in the dashboard",
                    "ignorePatterns only suppress image/CDN resources",
                    "Network APIs include l9_demo_tab=network query tags",
                ])

                // Add todo.
                HStack(spacing: 8) {
                    TextField("New todo…", text: $newTitle)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .cardStyle(cornerRadius: 8)
                        .onSubmit { Task { await createTodo() } }
                    PrimaryButton(title: "Add") { Task { await createTodo() } }
                        .fixedSize()
                }

                // Todo list.
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    VStack(spacing: 6) {
                        ForEach(todos) { todo in
                            HStack(spacing: 10) {
                                Button { Task { await toggleTodo(todo) } } label: {
                                    Text(todo.completed ? "✅" : "⬜").font(.system(size: 18))
                                }
                                .buttonStyle(.plain)
                                Text(todo.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(todo.completed ? Theme.textSecondary : Theme.textPrimary)
                                    .strikethrough(todo.completed)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(2)
                                Button { Task { await deleteTodo(todo.id) } } label: {
                                    Text("✕").font(.system(size: 16)).foregroundStyle(Theme.error)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .cardStyle(cornerRadius: 10)
                        }
                    }
                }

                SectionHeader(title: "Public API Requests")
                Hint("Sends public API requests across JSONPlaceholder, GitHub, and dog.ceo. These don't match ignorePatterns, so they create network spans and appear in the Last9 dashboard. Image/CDN patterns are still ignored. Filter by l9_demo_tab=network.")
                PrimaryButton(title: publicApiLoading ? "Sending public API requests…" : "Run Public API Demo",
                              disabled: publicApiLoading) {
                    Task { await runPublicApiDemos() }
                }

                SectionHeader(title: "Tracked Network Requests")
                Hint("Sends requests that do not match ignorePatterns, so these create network spans and appear in the Last9 dashboard. Filter by l9_demo_tab=network or l9_demo_request.")
                PrimaryButton(title: trackedLoading ? "Sending tracked requests…" : "Run Tracked Requests Demo",
                              disabled: trackedLoading) {
                    Task { await runTrackedNetworkDemos() }
                }

                // API log.
                if !results.isEmpty {
                    SectionHeader(title: "API Log")
                    ForEach(results.prefix(10)) { r in
                        ApiResultCard(label: r.label, status: r.status,
                                      durationMs: r.durationMs, ok: r.ok,
                                      detail: r.error ?? r.body)
                    }
                }
            }
            .navigationTitle("Todos")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { if loading { await loadTodos() } }
    }

    // MARK: - CRUD

    private func loadTodos() async {
        let r = await ApiClient.api("GET", "/todos?_limit=10",
                                    tags: .init(tab: .network, name: "todos-list"))
        todos = (try? JSONDecoder().decode([Todo].self, from: Data((r.body ?? "[]").utf8))) ?? []
        results.insert(r, at: 0)
        EventLog.shared.add("GET /todos → \(r.status) (\(r.durationMs)ms)")
        loading = false
    }

    private func createTodo() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let r = await ApiClient.api("POST", "/todos",
                                    body: ["title": title, "completed": false, "userId": 1],
                                    tags: .init(tab: .network, name: "todo-create"))
        results.insert(r, at: 0)
        EventLog.shared.add("POST /todos → \(r.status) (\(r.durationMs)ms)")
        if let created = try? JSONDecoder().decode(Todo.self, from: Data((r.body ?? "{}").utf8)) {
            todos.insert(Todo(userId: created.userId, id: created.id, title: title, completed: false), at: 0)
        }
        newTitle = ""
    }

    private func toggleTodo(_ todo: Todo) async {
        let r = await ApiClient.api("PATCH", "/todos/\(todo.id)",
                                    body: ["completed": !todo.completed],
                                    tags: .init(tab: .network, name: "todo-toggle"))
        results.insert(r, at: 0)
        EventLog.shared.add("PATCH /todos/\(todo.id) → \(r.status) (\(r.durationMs)ms)")
        if let idx = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[idx].completed.toggle()
        }
    }

    private func deleteTodo(_ id: Int) async {
        let r = await ApiClient.api("DELETE", "/todos/\(id)",
                                    tags: .init(tab: .network, name: "todo-delete"))
        results.insert(r, at: 0)
        EventLog.shared.add("DELETE /todos/\(id) → \(r.status) (\(r.durationMs)ms)")
        todos.removeAll { $0.id == id }
    }

    // MARK: - Demos

    private func runPublicApiDemos() async {
        publicApiLoading = true
        var collected: [ApiResult] = []
        await withTaskGroup(of: ApiResult.self) { group in
            for demo in PUBLIC_API_DEMOS {
                let name = "public-" + demo.label.replacingOccurrences(of: " ", with: "-").lowercased()
                group.addTask {
                    await ApiClient.timedGet(label: "PUBLIC API \(demo.label)", url: demo.url,
                                             tags: .init(tab: .network, name: name))
                }
            }
            for await r in group { collected.append(r) }
        }
        results.insert(contentsOf: collected, at: 0)
        EventLog.shared.add("public API demo → \(collected.count) captured requests")
        publicApiLoading = false
    }

    private func runTrackedNetworkDemos() async {
        trackedLoading = true
        var collected: [ApiResult] = []
        await withTaskGroup(of: ApiResult.self) { group in
            for demo in TRACKED_NETWORK_DEMOS {
                let name = demo.label.replacingOccurrences(of: " ", with: "-").lowercased()
                group.addTask {
                    await ApiClient.timedGet(label: "TRACKED \(demo.label)", url: demo.url,
                                             tags: .init(tab: .network, name: name))
                }
            }
            for await r in group { collected.append(r) }
        }
        results.insert(contentsOf: collected, at: 0)
        EventLog.shared.add("tracked demo → \(collected.count) captured requests")
        trackedLoading = false
    }
}
