import Foundation

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  API helper — every call goes through URLSession so the SDK's network
//  instrumentation captures it with W3C traceparent headers.
//  Uses JSONPlaceholder (https://jsonplaceholder.typicode.com/guide/).
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// JSONPlaceholder mock API base.
let API_BASE = "https://jsonplaceholder.typicode.com"

/// Public-API demo targets (Network tab → "Run Public API Demo").
let PUBLIC_API_DEMOS: [(label: String, url: String)] = [
    ("todos limit", "\(API_BASE)/todos?_limit=1"),
    ("comments by post", "\(API_BASE)/comments?postId=1"),
    ("user detail", "\(API_BASE)/users/1"),
    ("album detail", "\(API_BASE)/albums/1"),
    ("GitHub zen", "https://api.github.com/zen"),
    ("random dog image API", "https://dog.ceo/api/breeds/image/random"),
]

/// Tracked-request demo targets (Network tab → "Run Tracked Requests Demo").
let TRACKED_NETWORK_DEMOS: [(label: String, url: String)] = [
    ("tracked posts list", "\(API_BASE)/posts?_limit=3"),
    ("tracked todo detail", "\(API_BASE)/todos/2"),
    ("tracked GitHub rate limit", "https://api.github.com/rate_limit"),
]

// MARK: - Models

struct Post: Identifiable, Decodable {
    let userId: Int?
    let id: Int
    let title: String
    let body: String
}

struct Comment: Identifiable, Decodable {
    let postId: Int?
    let id: Int
    let name: String
    let email: String
    let body: String
}

struct User: Identifiable, Decodable {
    let id: Int
    let name: String
    let email: String
}

struct Todo: Identifiable, Decodable {
    let userId: Int?
    let id: Int
    let title: String
    var completed: Bool
}

/// Result of a network request, rendered as an `ApiResultCard`.
struct ApiResult: Identifiable {
    let id = UUID()
    let label: String
    let method: String
    let path: String
    let status: Int
    let ok: Bool
    let durationMs: Int
    let error: String?
    let body: String?
}

/// Demo request tags appended as query params + headers so requests are easy
/// to filter in the Last9 dashboard (`l9_demo_tab`, `l9_demo_request`).
struct DemoRequestTags {
    enum Tab: String { case home, network }
    let tab: Tab
    let name: String
}

// MARK: - API client

enum ApiClient {

    /// Tag a URL with `l9_demo`, `l9_demo_tab`, `l9_demo_request` query params.
    static func demoUrl(_ url: String, tags: DemoRequestTags) -> URL {
        guard var components = URLComponents(string: url) else {
            return URL(string: url)!
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "l9_demo", value: "true"))
        items.append(URLQueryItem(name: "l9_demo_tab", value: tags.tab.rawValue))
        items.append(URLQueryItem(name: "l9_demo_request", value: tags.name))
        components.queryItems = items
        return components.url ?? URL(string: url)!
    }

    static func demoHeaders(_ tags: DemoRequestTags) -> [String: String] {
        [
            "Content-Type": "application/json; charset=UTF-8",
            "X-L9-Demo": "true",
            "X-L9-Demo-Tab": tags.tab.rawValue,
            "X-L9-Demo-Request": tags.name,
        ]
    }

    /// Perform a request against `API_BASE` and return a timed `ApiResult`.
    static func api(_ method: String, _ path: String,
                    body: [String: Any]? = nil,
                    tags: DemoRequestTags? = nil) async -> ApiResult {
        let tags = tags ?? DemoRequestTags(tab: .network, name: "\(method) \(path)")
        let url = demoUrl("\(API_BASE)\(path)", tags: tags)
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (k, v) in demoHeaders(tags) { request.setValue(v, forHTTPHeaderField: k) }
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }

        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            return ApiResult(
                label: "\(method) \(path)", method: method, path: path,
                status: status, ok: (200..<300).contains(status),
                durationMs: ms, error: nil, body: String(text.prefix(500))
            )
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return ApiResult(
                label: "\(method) \(path)", method: method, path: path,
                status: 0, ok: false, durationMs: ms,
                error: error.localizedDescription, body: nil
            )
        }
    }

    /// GET a URL, decode the body to `T`, and return both the data and a timed
    /// `ApiResult` (used by the Home tab's parallel TTFD requests).
    static func timedJson<T: Decodable>(_ label: String, _ url: String,
                                        tags: DemoRequestTags,
                                        as type: T.Type) async -> (data: T?, result: ApiResult) {
        let requestUrl = demoUrl(url, tags: tags)
        var request = URLRequest(url: requestUrl)
        for (k, v) in demoHeaders(tags) { request.setValue(v, forHTTPHeaderField: k) }

        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            let decoded = try? JSONDecoder().decode(T.self, from: data)
            return (decoded, ApiResult(
                label: label, method: "GET", path: requestUrl.absoluteString,
                status: status, ok: (200..<300).contains(status),
                durationMs: ms, error: nil, body: String(text.prefix(500))
            ))
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return (nil, ApiResult(
                label: label, method: "GET", path: requestUrl.absoluteString,
                status: 0, ok: false, durationMs: ms,
                error: error.localizedDescription, body: nil
            ))
        }
    }

    /// Fire a single GET (no decode) and return a labeled `ApiResult`.
    static func timedGet(label: String, url: String, tags: DemoRequestTags) async -> ApiResult {
        let requestUrl = demoUrl(url, tags: tags)
        var request = URLRequest(url: requestUrl)
        for (k, v) in demoHeaders(tags) { request.setValue(v, forHTTPHeaderField: k) }

        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            return ApiResult(
                label: label, method: "GET", path: requestUrl.absoluteString,
                status: status, ok: (200..<300).contains(status),
                durationMs: ms, error: nil, body: String(text.prefix(500))
            )
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return ApiResult(
                label: label, method: "GET", path: requestUrl.absoluteString,
                status: 0, ok: false, durationMs: ms,
                error: error.localizedDescription, body: nil
            )
        }
    }
}
