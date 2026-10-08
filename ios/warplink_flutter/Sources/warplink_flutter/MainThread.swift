import Foundation

/// Runs `work` now when already on the main thread, else on it.
///
/// Method replies and event sink writes belong on the platform thread
/// (contract section 7).
func runOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
