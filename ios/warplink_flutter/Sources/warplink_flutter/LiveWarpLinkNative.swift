import Foundation
import WarpLink

/// Forwards every call to the native WarpLink SDK singleton.
struct LiveWarpLinkNative: WarpLinkNative {
    var isConfigured: Bool { WarpLink.isConfigured }
    var isAttributionComplete: Bool { WarpLink.isAttributionComplete }
    var attributionResult: WarpLinkDeepLink? { WarpLink.attributionResult }
    var sdkVersion: String { WarpLink.sdkVersion }

    func configure(apiKey: String, options: WarpLinkOptions) {
        WarpLink.configure(apiKey: apiKey, options: options)
    }

    func handleDeepLink(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        WarpLink.handleDeepLink(url, completion: completion)
    }

    func checkDeferredDeepLink(
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        WarpLink.checkDeferredDeepLink(completion: completion)
    }

    func isWarpLinkURL(_ url: URL) -> Bool {
        WarpLink.isWarpLinkURL(url)
    }
}
