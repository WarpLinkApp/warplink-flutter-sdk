import Foundation

/// Everything the plugin keeps for the whole process (contract section 11,
/// rule 1). Engines hold a reference to it and own nothing of their own.
final class PluginProcess: @unchecked Sendable {
    static let shared = PluginProcess(native: LiveWarpLinkNative())

    let native: WarpLinkNative
    let classifier: LinkClassifier
    let ledger: ArrivalLedger
    let verdict = LaunchVerdict()
    let ingress: ArrivalIngress
    let configurator: NativeConfigurator

    init(
        native: WarpLinkNative,
        matcher: PreConfigureLinkMatcher = PreConfigureLinkMatcher(),
        declaresScenes: Bool = PluginProcess.infoPlistDeclaresScenes,
        clock: @escaping () -> Int = ArrivalLedger.uptimeMs,
        turn: @escaping () -> Int = RunLoopTurn().current,
        log: @escaping (String) -> Void = ArrivalLedger.debugLog
    ) {
        let classifier = LinkClassifier(matcher: matcher, native: native)
        let ledger = ArrivalLedger(
            isWarpLink: { classifier.isWarpLink($0) },
            clock: clock,
            log: log
        )
        self.native = native
        self.classifier = classifier
        self.ledger = ledger
        self.ingress = ArrivalIngress(
            ledger: ledger,
            verdict: verdict,
            classifier: classifier,
            declaresScenes: declaresScenes,
            deliveries: DeliveryLog(turn: turn)
        )
        self.configurator = NativeConfigurator(native: native, ledger: ledger)
    }

    /// Whether the host app adopted the scene life cycle, so UIKit hands every
    /// URL to a scene and none to the application delegate.
    static var infoPlistDeclaresScenes: Bool {
        Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil
    }
}
