import Foundation

@testable import warplink_flutter
@testable import WarpLink

/// A scripted stand-in for the native SDK singleton.
final class FakeWarpLinkNative: WarpLinkNative, @unchecked Sendable {
    var isConfigured = false
    var isAttributionComplete = false
    var attributionResult: WarpLinkDeepLink?
    var deferredCheckStatus: DeferredCheckStatus = .notChecked
    var sdkVersion = "1.2.0"
    var lastTetherTestReceipt: String?
    var knownHosts: Set<String> = ["aplnk.to"]
    var resolveResult: Result<WarpLinkDeepLink, WarpLinkError> = .failure(.linkNotFound)
    var deferredResult: Result<WarpLinkDeepLink?, WarpLinkError> = .success(nil)
    var redeemResult: Result<WarpLinkDeepLink?, WarpLinkError> = .success(nil)
    var claimResult: Result<ReferralClaimResult, WarpLinkError> = .success(.none)
    var tetherResult: Result<TetherReadResult, WarpLinkError> = .success(.noCode(.clipboardEmpty))
    var clearResult: Result<Void, WarpLinkError> = .success(())
    /// While `true`, a resolve waits in `heldResolves` until the test finishes it.
    var holdResolves = false

    private(set) var configureCalls: [(apiKey: String, options: WarpLinkOptions)] = []
    private(set) var resolveCalls: [URL] = []
    private(set) var redeemCalls: [String] = []
    private(set) var claimCalls: [String] = []
    private(set) var tetherReads = 0
    private var heldResolves: [(Result<WarpLinkDeepLink, WarpLinkError>) -> Void] = []

    var latestOptions: WarpLinkOptions? { configureCalls.last?.options }

    func configure(apiKey: String, options: WarpLinkOptions) {
        configureCalls.append((apiKey, options))
        isConfigured = true
    }

    func handleDeepLink(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        resolveCalls.append(url)
        if holdResolves {
            heldResolves.append(completion)
        } else {
            completion(resolveResult)
        }
    }

    /// Completes the oldest held resolve.
    func finishHeldResolve(_ result: Result<WarpLinkDeepLink, WarpLinkError>) {
        heldResolves.removeFirst()(result)
    }

    func checkDeferredDeepLink(
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        completion(deferredResult)
    }

    func redeemInvitation(
        text: String,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        redeemCalls.append(text)
        completion(redeemResult)
    }

    func claimReferral(
        installerId: String,
        completion: @escaping (Result<ReferralClaimResult, WarpLinkError>) -> Void
    ) {
        claimCalls.append(installerId)
        completion(claimResult)
    }

    func readTether(
        completion: @escaping (Result<TetherReadResult, WarpLinkError>) -> Void
    ) {
        tetherReads += 1
        completion(tetherResult)
    }

    func clearAttribution() -> Result<Void, WarpLinkError> {
        clearResult
    }

    func isWarpLinkURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), knownHosts.contains(host) else { return false }
        return url.pathComponents.filter { $0 != "/" }.count == 1
    }
}
