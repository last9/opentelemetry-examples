import Foundation
import Last9RUM

enum RUMConfig {
    static func make() -> L9RumConfig {
        L9RumConfig(
            baseUrl: urlValue("LAST9_BASE_URL", defaultValue: "otlp-ext-aps1.last9.io/v1/otlp/organizations/<org>"),
            clientToken: value("LAST9_CLIENT_TOKEN", defaultValue: "<your-client-token>"),
            serviceName: "ios-rum-spm-demo",
            serviceVersion: "1.0.0",
            deploymentEnvironment: "development",
            debugLogs: true,
            origin: urlValue("LAST9_ORIGIN", defaultValue: "app.last9.io")
        )
    }

    private static func value(_ key: String, defaultValue: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? defaultValue
    }

    private static func urlValue(_ key: String, defaultValue: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? defaultValue
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return raw
        }
        return "https://\(raw)"
    }
}
