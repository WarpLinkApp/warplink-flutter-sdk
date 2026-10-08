import Foundation

/// Applies `configure` to the native SDK, process-wide.
///
/// An identical configuration is applied once: a second engine, or a Dart hot
/// restart, that configures the same way finds native already set up. A
/// changed one advances the ledger's epoch after native took it. A native
/// `configure` never cancels a manual `handleDeepLink`, so a resolve already in
/// flight settles under the old configuration, and the ledger discards that
/// answer and resolves again under the new one.
final class NativeConfigurator: @unchecked Sendable {
    private let native: WarpLinkNative
    private let ledger: ArrivalLedger
    private let lock = NSLock()
    private var applied: ConfigureRequest?

    init(native: WarpLinkNative, ledger: ArrivalLedger) {
        self.native = native
        self.ledger = ledger
    }

    func apply(_ request: ConfigureRequest) {
        lock.lock()
        let isReused = applied == request && native.isConfigured
        applied = request
        lock.unlock()
        guard !isReused else { return }
        native.configure(apiKey: request.apiKey, options: request.nativeOptions)
        ledger.advanceEpoch()
    }
}
