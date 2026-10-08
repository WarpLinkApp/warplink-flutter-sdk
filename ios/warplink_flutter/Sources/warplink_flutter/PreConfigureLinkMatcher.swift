import Foundation

/// Classifies a URL as a WarpLink link before the native SDK is configured.
///
/// Native `WarpLink.isWarpLinkURL` knows only `aplnk.to` until `configure`
/// runs, because it reads the `WarpLinkDomains` Info.plist entry during
/// `configure`. A cold URL arrives before Dart can call `configure`, so the
/// plugin reads the same Info.plist entry itself and applies the native rules:
/// an exact, case-folded host match and exactly one path segment. It adds one
/// rule of its own: every app has its own link host, `{handle}.aplnk.to`, so a
/// single-label subdomain of `aplnk.to` counts without an entry.
struct PreConfigureLinkMatcher: Sendable {
    static let defaultDomain = "aplnk.to"
    static let infoPlistKey = "WarpLinkDomains"

    private let declared: @Sendable () -> Any?

    init(declared: @escaping @Sendable () -> Any? = {
        Bundle.main.object(forInfoDictionaryKey: PreConfigureLinkMatcher.infoPlistKey)
    }) {
        self.declared = declared
    }

    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
            domains.contains(host) || Self.isAppSubdomain(host)
        else { return false }
        return Self.hasSingleSegment(url)
    }

    /// `{handle}.aplnk.to`: exactly one non-empty label before the default
    /// domain.
    private static func isAppSubdomain(_ host: String) -> Bool {
        let suffix = "." + defaultDomain
        guard host.hasSuffix(suffix) else { return false }
        let handle = host.dropLast(suffix.count)
        return !handle.isEmpty && !handle.contains(".")
    }

    private var domains: Set<String> {
        var set: Set<String> = [Self.defaultDomain]
        set.formUnion(Self.entries(from: declared()).compactMap(Self.normalize))
        return set
    }

    /// The array form, filtered entry by entry, or the comma separated string
    /// form. Anything else declares nothing.
    private static func entries(from value: Any?) -> [String] {
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        if let single = value as? String { return single.split(separator: ",").map(String.init) }
        return []
    }

    /// The host of one entry: scheme, credentials, path, and port dropped.
    private static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let separator = value.range(of: "://") {
            value = String(value[separator.upperBound...])
        } else if value.hasPrefix("//") {
            value = String(value.dropFirst(2))
        }
        var host = String(value.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if let colon = host.lastIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            if !port.isEmpty, port.allSatisfy({ $0.isASCII && $0.isNumber }) {
                host = String(host[..<colon])
            }
        }
        return host.isEmpty ? nil : host
    }

    private static func hasSingleSegment(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let slug = parts.first else { return false }
        return !slug.isEmpty && !slug.contains("/")
    }
}
