import Foundation
@_spi(Flutter) import WarpLink

/// Forwards every call to the native WarpLink SDK singleton.
struct LiveWarpLinkNative: WarpLinkNative {
    var isConfigured: Bool { WarpLink.isConfigured }
    var isAttributionComplete: Bool { WarpLink.isAttributionComplete }
    var deferredCheckStatus: DeferredCheckStatus { WarpLink.deferredCheckStatus }
    var attributionResult: WarpLinkDeepLink? { WarpLink.attributionResult }
    var sdkVersion: String { WarpLink.sdkVersion }
    var lastTetherTestReceipt: String? { WarpLink.lastTetherTestReceipt }

    func configure(apiKey: String, options: WarpLinkOptions) {
        // Tether reports this as the request's sdk_platform, not "ios".
        WarpLink.declareHostWrapper("flutter")
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

    func redeemInvitation(
        text: String,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        WarpLink.redeemInvitation(text: text, completion: completion)
    }

    func clearAttribution() -> Result<Void, WarpLinkError> {
        WarpLink.clearAttribution()
    }

    func claimReferral(
        installerId: String,
        completion: @escaping (Result<ReferralClaimResult, WarpLinkError>) -> Void
    ) {
        WarpLink.claimReferral(installerId: installerId, completion: completion)
    }

    func readTether(
        completion: @escaping (Result<TetherReadResult, WarpLinkError>) -> Void
    ) {
        WarpLink.readTether(completion: completion)
    }
}
