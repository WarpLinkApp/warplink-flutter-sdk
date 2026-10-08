import UIKit
import XCTest

@testable import warplink_flutter

/// The plugin's delegate entry points, with more than one engine attached.
final class PluginDelegateTests: XCTestCase {
    private let tap = link("https://aplnk.to/abc")
    private let foreign = link("https://example.com/abc")
    private let host = TestHost()

    private func makePlugin() -> WarpLinkFlutterPlugin {
        WarpLinkFlutterPlugin(process: host.process)
    }

    private func activity(_ url: URL) -> NSUserActivity {
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        return activity
    }

    func testDelegateReturnValuesClaimWarpLinkURLsOnly() {
        let plugin = makePlugin()
        host.finishLaunch()
        let app = UIApplication.shared
        XCTAssertTrue(plugin.application(app, open: tap))
        XCTAssertFalse(plugin.application(app, open: foreign))
        XCTAssertTrue(plugin.application(app, continue: activity(tap)) { _ in })
        XCTAssertFalse(plugin.application(app, continue: activity(foreign)) { _ in })
    }

    func testANonWebActivityIsNotAnArrival() {
        let plugin = makePlugin()
        host.finishLaunch()
        let other = NSUserActivity(activityType: "com.example.other")
        XCTAssertFalse(plugin.application(UIApplication.shared, continue: other) { _ in })
        XCTAssertTrue(host.ledger.slots.isEmpty)
    }

    func testLaunchNeverVetoed() {
        let plugin = makePlugin()
        XCTAssertTrue(plugin.application(UIApplication.shared, didFinishLaunchingWithOptions: [:]))
        XCTAssertTrue(host.process.verdict.isDecided)
    }

    func testTwoEnginesRecordOneDeliveryOnce() {
        let first = makePlugin()
        let second = makePlugin()
        host.finishLaunch()
        let app = UIApplication.shared
        for plugin in [first, second] {
            _ = plugin.application(app, open: tap)
            _ = plugin.application(app, open: foreign)
        }
        XCTAssertEqual(host.ledger.slots.map(\.entry.url), [tap, foreign])
    }

    func testTwoEnginesRecordOneActivityOnceAndAnswerTheSame() {
        let first = makePlugin()
        let second = makePlugin()
        host.finishLaunch()
        let app = UIApplication.shared
        XCTAssertTrue(first.application(app, continue: activity(tap)) { _ in })
        XCTAssertTrue(second.application(app, continue: activity(tap)) { _ in })
        XCTAssertEqual(host.ledger.slots.count, 1)
    }

    func testTheSecondEngineAloneStillRecordsADelivery() {
        _ = makePlugin()
        let second = makePlugin()
        host.finishLaunch()
        _ = second.application(UIApplication.shared, open: tap)
        XCTAssertEqual(host.ledger.slots.map(\.entry.url), [tap])
    }

    func testTheSameURLOnALaterTurnIsANewArrivalForEveryEngine() {
        let first = makePlugin()
        let second = makePlugin()
        host.finishLaunch()
        let app = UIApplication.shared
        for _ in 0..<2 {
            for plugin in [first, second] {
                _ = plugin.application(app, continue: activity(tap)) { _ in }
            }
            host.advanceTurn()
        }
        XCTAssertEqual(host.ledger.slots.count, 2)
    }

    func testSceneContextsInDifferentOrdersInOneTurnAreOneArrival() {
        host.finishLaunch()
        let other = link("https://aplnk.to/def")
        let ingress = host.ingress
        let forward = DeliveryIdentity(callback: .open, urls: [tap, other])
        let backward = DeliveryIdentity(callback: .open, urls: [other, tap])
        XCTAssertTrue(ingress.sceneOpen([tap, other], identity: forward))
        XCTAssertTrue(ingress.sceneOpen([other, tap], identity: backward))
        XCTAssertEqual(host.ledger.slots.map(\.entry.url), [tap, other])
    }

    func testAnApplicationOpenAndASceneOpenOfOneURLInOneTurnAreOneArrival() {
        host.finishLaunch()
        let ingress = host.ingress
        let identity = DeliveryIdentity(callback: .open, urls: [tap])
        XCTAssertTrue(ingress.applicationOpen(tap, identity: identity))
        XCTAssertTrue(ingress.sceneOpen([tap], identity: identity))
        XCTAssertEqual(host.ledger.slots.count, 1)
    }

    func testTwoCallbackKindsForOneURLInOneTurnAreTwoArrivals() {
        host.finishLaunch()
        let ingress = host.ingress
        XCTAssertTrue(ingress.sceneOpen([tap], identity: DeliveryIdentity(callback: .open, urls: [tap])))
        XCTAssertTrue(
            ingress.sceneContinue(tap, identity: DeliveryIdentity(callback: .continue, urls: [tap]))
        )
        XCTAssertEqual(host.ledger.slots.count, 2)
    }

    func testTheIdentityOfAURLSetIgnoresItsOrder() {
        let other = link("https://aplnk.to/def")
        XCTAssertEqual(
            DeliveryIdentity(callback: .open, urls: [tap, other]),
            DeliveryIdentity(callback: .open, urls: [other, tap])
        )
    }

    func testTheLogForgetsEveryDeliveryWhenTheTurnChanges() {
        var turn = 0
        let log = DeliveryLog(turn: { turn })
        let identity = DeliveryIdentity(callback: .open, urls: [tap])
        XCTAssertTrue(log.isFirstSighting(of: identity))
        XCTAssertFalse(log.isFirstSighting(of: identity))
        turn += 1
        XCTAssertTrue(log.isFirstSighting(of: identity))
    }

    func testTheRunLoopTurnAdvancesOnTheNextMainQueueDrain() {
        let clock = RunLoopTurn()
        let before = clock.current()
        XCTAssertEqual(clock.current(), before)
        let advanced = expectation(description: "next main queue block")
        DispatchQueue.main.async { advanced.fulfill() }
        wait(for: [advanced], timeout: 2)
        XCTAssertNotEqual(clock.current(), before)
    }
}
