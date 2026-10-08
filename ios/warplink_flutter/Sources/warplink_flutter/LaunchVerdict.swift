import Foundation

/// Whether this process knows yet if it has a launch arrival (contract
/// section 4.3).
///
/// `getPendingArrivals` waits for the verdict, so it never answers with a list
/// that lacks a launch entry still on its way. The verdict is process-wide and
/// holds once reached: a second engine answers at once.
final class LaunchVerdict: @unchecked Sendable {
    private let lock = NSLock()
    private var decided = false
    private var waiters: [() -> Void] = []

    var isDecided: Bool {
        lock.lock()
        defer { lock.unlock() }
        return decided
    }

    /// Runs `action` now when the verdict is in, else once it is.
    func whenDecided(_ action: @escaping () -> Void) {
        lock.lock()
        if decided {
            lock.unlock()
            action()
            return
        }
        waiters.append(action)
        lock.unlock()
    }

    /// Ends the launch window. Later calls change nothing.
    func decide() {
        lock.lock()
        guard !decided else {
            lock.unlock()
            return
        }
        decided = true
        let released = waiters
        waiters = []
        lock.unlock()
        released.forEach { action in runOnMain(action) }
    }
}
