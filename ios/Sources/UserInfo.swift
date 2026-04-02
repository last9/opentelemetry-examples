import Foundation

/// User identity for RUM session attribution.
///
/// Set via `Last9OTel.identify(...)`, injected into every span by `SessionSpanProcessor`.
/// Mirrors the browser SDK's `UserInfo` type.
public struct UserInfo {
    public var id: String?
    public var name: String?
    public var fullName: String?
    public var email: String?
    public var extraInfo: [String: String]

    public init(
        id: String? = nil,
        name: String? = nil,
        fullName: String? = nil,
        email: String? = nil,
        extraInfo: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.email = email
        self.extraInfo = extraInfo
    }
}
