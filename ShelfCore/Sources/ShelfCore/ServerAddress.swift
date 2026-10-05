import Foundation

/// A Kavita server origin and the `/api` root derived from what the user typed.
public struct ServerAddress: Hashable, Sendable {
    public let origin: URL
    public let apiRoot: URL
    /// Origin without a trailing slash, suitable to show in the UI and to store.
    public let display: String

    public init(userInput: String) throws {
        var trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw KavitaError.invalidServerURL
        }
        if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else {
            throw KavitaError.invalidServerURL
        }

        components.scheme = scheme
        var path = components.path
        if path.hasSuffix("/api") {
            path.removeLast(4)
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path
        components.query = nil
        components.fragment = nil

        guard let origin = components.url else {
            throw KavitaError.invalidServerURL
        }
        self.origin = origin
        guard let apiRoot = URL(string: origin.absoluteString + "/api") else {
            throw KavitaError.invalidServerURL
        }
        self.apiRoot = apiRoot
        self.display = origin.absoluteString
    }

    public func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL? {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let base = apiRoot.absoluteString.hasSuffix("/") ? apiRoot.absoluteString : apiRoot.absoluteString + "/"
        guard var components = URLComponents(string: base + relative) else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query.filter { $0.value != nil }
        }
        return components.url
    }
}
