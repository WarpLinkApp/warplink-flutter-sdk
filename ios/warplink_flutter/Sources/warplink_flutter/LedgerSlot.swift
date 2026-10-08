import Foundation

/// The native-side state of a ledger entry (contract section 4.1).
enum SlotState {
    /// Recorded, not resolved.
    case pending
    /// Resolve started, native request in flight.
    case resolving
    /// Answer stored.
    case settled(ArrivalOutcome)

    var label: String {
        switch self {
        case .pending: return "pending"
        case .resolving: return "resolving"
        case .settled: return "settled"
        }
    }
}

/// A ledger entry with its state, delivery flag, and the replies waiting on
/// its resolve. None of this is on the wire. `resolveEpoch` is the native
/// configuration epoch the running resolve started under.
struct LedgerSlot {
    let entry: ArrivalEntry
    var delivered = false
    var state = SlotState.pending
    var resolveEpoch = 0
    var waiters: [(ArrivalOutcome) -> Void] = []

    init(entry: ArrivalEntry) {
        self.entry = entry
    }
}
