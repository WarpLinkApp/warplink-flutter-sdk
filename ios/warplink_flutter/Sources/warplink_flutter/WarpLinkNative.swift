import Foundation
import WarpLink

/// The slice of the native WarpLink SDK this plugin drives.
///
/// The plugin calls only the public API. The protocol exists so the bridge
/// logic can run against a scripted stand-in in tests, because the native SDK
/// is a process-wide singleton. The plugin never calls `open` or `continue`:
/// Dart owns link dispatch.
protocol WarpLinkNative: Sendable {
    var isConfigured: Bool { get }
    var isAttributionComplete: Bool { get }
    var attributionResult: WarpLinkDeepLink? { get }
    var sdkVersion: String { get }

    func configure(apiKey: String, options: WarpLinkOptions)
    func handleDeepLink(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    )
    func checkDeferredDeepLink(
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    )
    func isWarpLinkURL(_ url: URL) -> Bool
}
