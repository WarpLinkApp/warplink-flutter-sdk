import Foundation

/// The size limit of the arrival ledger and the order in which it sheds
/// entries (contract section 11, rule 10).
enum ArrivalBound {
    static let capacity = 32

    /// The index of the one slot to drop so a new entry fits, or `nil` when
    /// no slot may go. The first rule that applies wins:
    ///
    /// 1. the oldest delivered entry, launch or not;
    /// 2. the oldest undelivered, non-launch entry that is not a WarpLink link;
    /// 3. the oldest undelivered, non-launch entry.
    ///
    /// An undelivered launch entry is never dropped.
    static func victim(in slots: [LedgerSlot], isWarpLink: (URL) -> Bool) -> Int? {
        if let delivered = slots.firstIndex(where: { $0.delivered }) { return delivered }
        let droppable = slots.indices.filter { !slots[$0].entry.isLaunch }
        return droppable.first { !isWarpLink(slots[$0].entry.url) } ?? droppable.first
    }
}
