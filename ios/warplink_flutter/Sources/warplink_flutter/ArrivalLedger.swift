import Foundation
import os

/// The process-wide record of every URL the host app received (contract
/// section 11).
///
/// Static state, not per engine: an engine is only a transport. An entry stays
/// until Dart claims its delivery, or until the bound sheds it. The ledger
/// calls no code of its own while it holds its lock, except the classifier the
/// bound needs.
final class ArrivalLedger: @unchecked Sendable {
    typealias Listener = ([String: Any]) -> Void

    let lock = NSLock()
    var slots: [LedgerSlot] = []
    private(set) var epoch = 0

    private var nextSeq = 0
    private var listeners: [UUID: Listener] = [:]
    private let isWarpLink: (URL) -> Bool
    private let clock: () -> Int
    private let log: (String) -> Void

    private static let logger = Logger(subsystem: "app.warplink.flutter", category: "arrivals")

    init(
        isWarpLink: @escaping (URL) -> Bool,
        clock: @escaping () -> Int = ArrivalLedger.uptimeMs,
        log: @escaping (String) -> Void = ArrivalLedger.debugLog
    ) {
        self.isWarpLink = isWarpLink
        self.clock = clock
        self.log = log
    }

    /// Milliseconds on `DispatchTime`'s monotonic uptime clock. Not a
    /// required-reason API.
    static func uptimeMs() -> Int {
        Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    static func debugLog(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    /// Advances the native configuration epoch. A resolve that started under an
    /// older epoch is stale when it settles.
    func advanceEpoch() {
        lock.lock()
        epoch += 1
        lock.unlock()
    }

    /// Records one OS delivery, then announces it to every listener. The entry
    /// is in the ledger before any listener hears of it.
    @discardableResult
    func record(url: URL, source: ArrivalSource, isLaunch: Bool) -> ArrivalEntry {
        lock.lock()
        let entry = ArrivalEntry(
            id: UUID().uuidString,
            url: url,
            source: source,
            isLaunch: isLaunch,
            seq: nextSeq,
            arrivedAtMs: clock()
        )
        nextSeq += 1
        let dropped = makeRoomLocked()
        slots.append(LedgerSlot(entry: entry))
        let targets = Array(listeners.values)
        lock.unlock()

        dropped?.waiters.forEach { waiter in runOnMain { waiter(.success(nil)) } }
        let payload = entry.payload
        runOnMain { targets.forEach { $0(payload) } }
        return entry
    }

    /// Every entry whose delivery nobody claimed, oldest first.
    func pending() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return slots.filter { !$0.delivered }.map { $0.entry.payload }
    }

    /// `true` to the first claim of a held id, `false` to every later one and
    /// to an id the ledger does not hold. A claim during a resolve marks the
    /// entry delivered and lets the request finish.
    func claimDelivery(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = slots.firstIndex(where: { $0.entry.id == id }),
            !slots[index].delivered
        else { return false }
        slots[index].delivered = true
        return true
    }

    func addListener(_ token: UUID, _ listener: @escaping Listener) {
        lock.lock()
        defer { lock.unlock() }
        listeners[token] = listener
    }

    func removeListener(_ token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        listeners[token] = nil
    }

    /// Drops one slot when the ledger is full. Its waiters get a no-match,
    /// because their entry is gone.
    private func makeRoomLocked() -> LedgerSlot? {
        guard slots.count >= ArrivalBound.capacity,
            let index = ArrivalBound.victim(in: slots, isWarpLink: isWarpLink)
        else { return nil }
        let dropped = slots.remove(at: index)
        log(
            "dropped arrival \(dropped.entry.id) "
                + "(state \(dropped.state.label), delivered \(dropped.delivered))"
        )
        return dropped
    }
}
