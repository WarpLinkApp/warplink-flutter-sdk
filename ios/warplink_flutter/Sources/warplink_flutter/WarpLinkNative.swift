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
    /// Where the deferred check stands. Sends no request.
    var deferredCheckStatus: DeferredCheckStatus { get }
    var attributionResult: WarpLinkDeepLink? { get }
    var sdkVersion: String { get }
    var lastTetherTestReceipt: String? { get }

    func configure(apiKey: String, options: WarpLinkOptions)
    func handleDeepLink(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    )
    func checkDeferredDeepLink(
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    )
    func isWarpLinkURL(_ url: URL) -> Bool
    func redeemInvitation(
        text: String,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    )
    /// A live key is a no-op success. Failure is `.decodingError` when a stored
    /// item could not be deleted.
    func clearAttribution() -> Result<Void, WarpLinkError>
    func claimReferral(
        installerId: String,
        completion: @escaping (Result<ReferralClaimResult, WarpLinkError>) -> Void
    )
    /// Reads the clipboard once and sends a Tether code, if one is there.
    func readTether(
        completion: @escaping (Result<TetherReadResult, WarpLinkError>) -> Void
    )
}
