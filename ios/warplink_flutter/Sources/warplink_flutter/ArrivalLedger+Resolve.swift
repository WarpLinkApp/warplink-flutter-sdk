import Foundation
import WarpLink

extension ArrivalLedger {
    /// Resolves the entry's URL through the public manual path, once.
    ///
    /// The first call for an id starts the one native request. Every later
    /// call joins it, or reads the stored answer, so one tap never reaches
    /// native twice. The native callback attaches to the entry, not to the
    /// channel that asked, so an engine that detaches strands nothing. An id
    /// the ledger does not hold answers no match.
    ///
    /// A request that settles under an older configuration epoch than the
    /// current one is discarded and sent again, so the stored answer always
    /// comes from the configuration in force when it settles.
    func resolve(
        _ id: String,
        using native: WarpLinkNative,
        completion: @escaping (ArrivalOutcome) -> Void
    ) {
        switch beginResolve(id, completion) {
        case .answered(let outcome):
            completion(outcome)
        case .joined:
            break
        case .start(let url):
            run(id, url, using: native)
        }
    }

    private enum Step {
        case answered(ArrivalOutcome)
        case joined
        case start(URL)
    }

    private enum Settlement {
        case done
        case restart(URL)
    }

    private func run(_ id: String, _ url: URL, using native: WarpLinkNative) {
        native.handleDeepLink(url) { [self] result in
            switch settle(id, with: Self.outcome(of: result)) {
            case .restart(let url): run(id, url, using: native)
            case .done: break
            }
        }
    }

    private func beginResolve(
        _ id: String,
        _ completion: @escaping (ArrivalOutcome) -> Void
    ) -> Step {
        lock.lock()
        defer { lock.unlock() }
        guard let index = slots.firstIndex(where: { $0.entry.id == id }) else {
            return .answered(.success(nil))
        }
        switch slots[index].state {
        case .settled(let outcome):
            return .answered(outcome)
        case .resolving:
            slots[index].waiters.append(completion)
            return .joined
        case .pending:
            slots[index].state = .resolving
            slots[index].resolveEpoch = epoch
            slots[index].waiters.append(completion)
            return .start(slots[index].entry.url)
        }
    }

    /// Stores the answer of a request that ran under the current epoch. A
    /// stale request returns the entry to pending instead: with replies
    /// waiting it starts again under the current epoch, else it waits for the
    /// next resolve.
    private func settle(_ id: String, with outcome: ArrivalOutcome) -> Settlement {
        lock.lock()
        guard let index = slots.firstIndex(where: { $0.entry.id == id }) else {
            lock.unlock()
            return .done
        }
        if slots[index].resolveEpoch != epoch {
            slots[index].state = .pending
            guard !slots[index].waiters.isEmpty else {
                lock.unlock()
                return .done
            }
            slots[index].state = .resolving
            slots[index].resolveEpoch = epoch
            let url = slots[index].entry.url
            lock.unlock()
            return .restart(url)
        }
        slots[index].state = .settled(outcome)
        let waiters = slots[index].waiters
        slots[index].waiters = []
        lock.unlock()
        waiters.forEach { waiter in runOnMain { waiter(outcome) } }
        return .done
    }

    private static func outcome(
        of result: Result<WarpLinkDeepLink, WarpLinkError>
    ) -> ArrivalOutcome {
        switch result {
        case .success(let link): return .success(DeepLinkPayload.deepLink(link))
        case .failure(let error): return .failure(ContractError.from(error))
        }
    }
}
