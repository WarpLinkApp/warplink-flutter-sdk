import Foundation
import WarpLink

/// Builds the deferred check status reply of the channel contract (section
/// 3.6): `state`, plus `retryAt` in epoch milliseconds for `waiting` only.
enum DeferredStatusPayload {
    static func status(_ status: DeferredCheckStatus) -> [String: Any] {
        switch status {
        case .notChecked: return ["state": "notChecked"]
        case .checking: return ["state": "checking"]
        case .matched: return ["state": "matched"]
        case .noMatch: return ["state": "noMatch"]
        case .waiting(let retryAt):
            return ["state": "waiting", "retryAt": Int((retryAt.timeIntervalSince1970 * 1000).rounded())]
        case .skippedOldInstall: return ["state": "skippedOldInstall"]
        case .stopped: return ["state": "stopped"]
        }
    }
}
