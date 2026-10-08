import Foundation

/// Decides whether a URL is a WarpLink link.
///
/// Native `isWarpLinkURL` knows the declared and verified domains only after
/// `configure`, and an arrival can land before Dart calls it. The plugin's own
/// matcher covers that window, so a URL counts when either side says so.
struct LinkClassifier: Sendable {
    private let matcher: PreConfigureLinkMatcher
    private let native: WarpLinkNative

    init(matcher: PreConfigureLinkMatcher, native: WarpLinkNative) {
        self.matcher = matcher
        self.native = native
    }

    func isWarpLink(_ url: URL) -> Bool {
        matcher.matches(url) || native.isWarpLinkURL(url)
    }
}
