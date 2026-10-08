import Foundation

/// Turns the OS callbacks into ledger entries (contract section 11, rules 5
/// and 6).
///
/// One OS delivery produces one arrival. With scenes, the scene callbacks are
/// the only source for a delivery a scene handles, and the application
/// delegate is the source only when no scene does. A delivery that reaches the
/// plugin more than once, because each engine registers its own instance, is
/// told apart by the identity of the delivered objects. A later tap on the same
/// URL is always a new arrival: nothing here compares URLs or times.
///
/// Every method answers whether the plugin claims the delivery. A WarpLink URL
/// is claimed so Flutter's router does not also route it, and a foreign URL is
/// not. A foreign URL is still recorded: Dart classifies it.
final class ArrivalIngress: @unchecked Sendable {
    private typealias Delivery = (url: URL, source: ArrivalSource)

    private let ledger: ArrivalLedger
    private let verdict: LaunchVerdict
    private let classifier: LinkClassifier
    private let deliveries: DeliveryLog
    private let declaresScenes: Bool
    private let lock = NSLock()
    private var sceneSeen = false

    init(
        ledger: ArrivalLedger,
        verdict: LaunchVerdict,
        classifier: LinkClassifier,
        declaresScenes: Bool,
        deliveries: DeliveryLog
    ) {
        self.ledger = ledger
        self.verdict = verdict
        self.classifier = classifier
        self.declaresScenes = declaresScenes
        self.deliveries = deliveries
    }

    // MARK: - Application delegate

    /// A launch that carries a URL is not recorded here. UIKit follows it with
    /// an open or continue call, which is the delivery. A launch without one
    /// has no launch arrival, so the verdict is in.
    func applicationDidFinishLaunching(launchURLs: [URL]) {
        guard !handlesViaScene, launchURLs.isEmpty else { return }
        verdict.decide()
    }

    func applicationOpen(_ url: URL, identity: DeliveryIdentity? = nil) -> Bool {
        fromApplication([(url, .forOpenedURL(url))], identity)
    }

    func applicationContinue(_ url: URL, identity: DeliveryIdentity? = nil) -> Bool {
        fromApplication([(url, .universalLink)], identity)
    }

    // MARK: - Scene delegate

    /// The first connection of the process carries the launch. A connection
    /// with options but no URL ends the launch window. A connection without
    /// options leaves it open: another plugin may have consumed the URL
    /// first, and only the activation verdict can end the wait then.
    func sceneConnecting(
        activityURLs: [URL]?,
        contextURLs: [URL]?,
        identity: DeliveryIdentity? = nil
    ) -> Bool {
        markSceneSeen()
        guard activityURLs != nil || contextURLs != nil else { return false }
        let incoming =
            (activityURLs ?? []).map { Delivery($0, .universalLink) }
            + (contextURLs ?? []).map { Delivery($0, .forOpenedURL($0)) }
        return admit(incoming, mayBeLaunch: true, identity)
    }

    func sceneOpen(_ urls: [URL], identity: DeliveryIdentity? = nil) -> Bool {
        markSceneSeen()
        return admit(urls.map { Delivery($0, .forOpenedURL($0)) }, mayBeLaunch: false, identity)
    }

    func sceneContinue(_ url: URL, identity: DeliveryIdentity? = nil) -> Bool {
        markSceneSeen()
        return admit([Delivery(url, .universalLink)], mayBeLaunch: false, identity)
    }

    /// The app is active, so no launch delivery can still be on its way.
    func becameActive() {
        verdict.decide()
    }

    // MARK: - Admission

    private var handlesViaScene: Bool {
        lock.lock()
        defer { lock.unlock() }
        return declaresScenes || sceneSeen
    }

    private func markSceneSeen() {
        lock.lock()
        sceneSeen = true
        lock.unlock()
    }

    private func fromApplication(_ incoming: [Delivery], _ identity: DeliveryIdentity?) -> Bool {
        guard !handlesViaScene else { return claims(incoming) }
        return admit(incoming, mayBeLaunch: true, identity)
    }

    /// Records each URL, then ends the launch window. Only the first URL
    /// inside the window is the launch arrival. A repeat report of a
    /// delivery already recorded changes nothing and claims the same way.
    private func admit(
        _ incoming: [Delivery],
        mayBeLaunch: Bool,
        _ identity: DeliveryIdentity?
    ) -> Bool {
        if let identity, !deliveries.isFirstSighting(of: identity) {
            return claims(incoming)
        }
        var launchOpen = mayBeLaunch && !verdict.isDecided
        for delivery in incoming {
            ledger.record(url: delivery.url, source: delivery.source, isLaunch: launchOpen)
            launchOpen = false
        }
        verdict.decide()
        return claims(incoming)
    }

    private func claims(_ incoming: [Delivery]) -> Bool {
        incoming.contains { classifier.isWarpLink($0.url) }
    }
}
