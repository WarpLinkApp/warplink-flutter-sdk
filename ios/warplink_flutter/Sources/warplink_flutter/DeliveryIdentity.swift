import Foundation

/// Which OS delivery a callback reports: the kind of callback plus the URLs it
/// carries, as one normalized string. The application delegate and the scene
/// delegate share a kind, so one URL reported by both is one delivery. The URLs
/// are sorted, so the iteration order of a scene's URL contexts never matters.
struct DeliveryIdentity: Hashable {
    enum Callback {
        case open
        case `continue`
        case connect
    }

    let callback: Callback
    let urls: String

    init(callback: Callback, urls: [URL]) {
        self.callback = callback
        self.urls = urls.map(\.absoluteString).sorted().joined(separator: "\n")
    }
}

/// Counts main run-loop turns. A value read in one turn differs from a value
/// read in any later turn. Flutter fans one OS callback out to every plugin
/// instance synchronously inside one turn, and two taps never share a turn.
final class RunLoopTurn: @unchecked Sendable {
    private let lock = NSLock()
    private var turn = 0
    private var advanceScheduled = false

    /// The current turn. The first read of a turn schedules the next one.
    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
        if !advanceScheduled {
            advanceScheduled = true
            DispatchQueue.main.async { [self] in advance() }
        }
        return turn
    }

    private func advance() {
        lock.lock()
        turn += 1
        advanceScheduled = false
        lock.unlock()
    }
}

/// The deliveries seen in the current turn, so a callback that every engine's
/// plugin instance receives is recorded once. The set is cleared when the turn
/// changes.
final class DeliveryLog: @unchecked Sendable {
    private let turn: () -> Int
    private let lock = NSLock()
    private var seenTurn: Int?
    private var seen: Set<DeliveryIdentity> = []

    init(turn: @escaping () -> Int) {
        self.turn = turn
    }

    /// `true` for the first report of a delivery in a turn, `false` for a repeat.
    func isFirstSighting(of identity: DeliveryIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = turn()
        if seenTurn != now {
            seenTurn = now
            seen.removeAll()
        }
        return seen.insert(identity).inserted
    }
}
