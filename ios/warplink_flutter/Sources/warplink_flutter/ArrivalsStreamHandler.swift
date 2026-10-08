import Flutter
import Foundation

/// The arrivals event channel of one engine (contract section 4.2).
///
/// The first event after `onListen` is `{ "type": "ready" }`. Every entry the
/// ledger records afterwards is announced as one event. Events are
/// notifications: the ledger is the queue, so nothing is buffered here.
final class ArrivalsStreamHandler: NSObject, FlutterStreamHandler, @unchecked Sendable {
    private let ledger: ArrivalLedger
    private let token = UUID()
    private let lock = NSLock()
    private var sink: FlutterEventSink?

    init(ledger: ArrivalLedger) {
        self.ledger = ledger
        super.init()
    }

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        setSink(events)
        events(["type": "ready"])
        ledger.addListener(token) { [weak self] payload in self?.send(payload) }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        invalidate()
        return nil
    }

    /// Stops all writes. Called when the engine detaches.
    func invalidate() {
        ledger.removeListener(token)
        setSink(nil)
    }

    private func setSink(_ newSink: FlutterEventSink?) {
        lock.lock()
        sink = newSink
        lock.unlock()
    }

    private func send(_ payload: [String: Any]) {
        lock.lock()
        let target = sink
        lock.unlock()
        target?(payload)
    }
}
