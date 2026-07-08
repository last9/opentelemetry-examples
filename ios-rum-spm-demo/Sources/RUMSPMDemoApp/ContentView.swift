import Last9RUM
import SwiftUI

public struct ContentView: View {
    @State private var log: [String] = ["SDK not initialized"]

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last9 RUM SPM Demo")
                    .font(.title.bold())
                Text("Initializes Last9RUM from the app entry path, makes URLSession calls, and demonstrates v0.9.0 shutdown/re-init lifecycle APIs.")
                    .font(.body)

                Button("Initialize SDK") {
                    L9Rum.shared.initialize(config: RUMConfig.make())
                    append("SDK initialized")
                }
                .buttonStyle(.borderedProminent)

                Button("GET todo") {
                    Task { await call("https://jsonplaceholder.typicode.com/todos/1") }
                }
                .buttonStyle(.bordered)

                Button("GET httpbin") {
                    Task { await call("https://httpbin.org/get") }
                }
                .buttonStyle(.bordered)

                Button("Set per-flow attributes") {
                    L9Rum.shared.spanAttributes([
                        "example.flow": "spm-demo",
                        "feature.flag": "v0.9.0-lifecycle",
                    ])
                    append("Per-flow span attributes set")
                }
                .buttonStyle(.bordered)

                Button("Check active state") {
                    append("SDK active: \(L9Rum.shared.isActive())")
                }
                .buttonStyle(.bordered)

                Button("Flush SDK") {
                    L9Rum.shared.flush()
                    append("Flush requested")
                }
                .buttonStyle(.bordered)

                Button("Shutdown SDK") {
                    L9Rum.shared.shutdown()
                    append("SDK shutdown complete; active: \(L9Rum.shared.isActive())")
                }
                .buttonStyle(.bordered)

                List(log, id: \.self) { line in
                    Text(line).font(.caption.monospaced())
                }
            }
            .padding()
            .navigationTitle("RUM SPM")
        }
    }

    @MainActor
    private func append(_ message: String) {
        log.append(message)
    }

    private func call(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            append("GET \(url.host ?? urlString) -> HTTP \(status)")
        } catch {
            L9Rum.shared.captureError(error, context: ["example.url": urlString])
            append("GET \(urlString) failed: \(error.localizedDescription)")
        }
    }
}
