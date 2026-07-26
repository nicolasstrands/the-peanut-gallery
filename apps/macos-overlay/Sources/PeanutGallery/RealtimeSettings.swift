import Foundation

/// Where the overlay connects. Resolved at connect time so a user can point the
/// app at their own Cloudflare deployment from the menu bar, with no rebuild and
/// nothing baked into the repository.
enum RealtimeSettings {
    static let defaultsKey = "peanutGallery.realtimeURL"
    private static let environmentKey = "PEANUT_GALLERY_REALTIME_URL"

    /// Set for local development. Takes precedence over the stored value, which
    /// is why the Settings dialog reports itself as read-only while it is set.
    static var environmentOverride: String? {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey] else { return nil }
        return normalized(raw)
    }

    static var storedURL: String? {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        return normalized(raw)
    }

    /// The endpoint to connect to, or nil when the app has not been set up yet.
    static var resolvedURL: String? { environmentOverride ?? storedURL }

    static var isOverriddenByEnvironment: Bool { environmentOverride != nil }

    static func store(_ value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }

    /// Accepts what Wrangler prints (`https://…workers.dev`) as well as explicit
    /// `ws://`/`wss://` URLs and bare hosts, returning a scheme-correct origin
    /// with no trailing slash. Returns nil when the input cannot be a WebSocket
    /// origin, so callers can show an error instead of connecting to nonsense.
    static func normalized(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("https://") {
            value = "wss://" + value.dropFirst("https://".count)
        } else if value.hasPrefix("http://") {
            value = "ws://" + value.dropFirst("http://".count)
        } else if !value.hasPrefix("wss://") && !value.hasPrefix("ws://") {
            // A bare host is far more likely to be a local dev server than a
            // public one when it points at loopback, so pick the scheme to match.
            value = isLoopback(value) ? "ws://" + value : "wss://" + value
        }

        guard let url = URL(string: value),
              let host = url.host,
              !host.isEmpty,
              url.query == nil,
              url.fragment == nil
        else { return nil }

        return value
    }

    /// Short host[:port] label for the menu bar. A `workers.dev` address collapses
    /// to its account subdomain: the worker name comes from wrangler.jsonc and is
    /// the same for everyone, so the subdomain is the part that says whose
    /// deployment this is. Every other host is left alone.
    static func displayName(for value: String) -> String {
        guard let url = URL(string: value), let host = url.host else { return value }
        let label = shortenedHost(host)
        guard let port = url.port else { return label }
        return "\(label):\(port)"
    }

    private static func shortenedHost(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 3, Array(labels.suffix(2)) == ["workers", "dev"] else { return host }
        return labels.suffix(3).joined(separator: ".")
    }

    private static func isLoopback(_ value: String) -> Bool {
        let hostAndPort = value.split(separator: "/").first.map(String.init) ?? value
        let host = hostAndPort.split(separator: ":").first.map(String.init) ?? hostAndPort
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
