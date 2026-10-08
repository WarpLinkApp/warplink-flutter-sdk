import XCTest

@testable import warplink_flutter

final class ArrivalIngressTests: XCTestCase {
    private let tap = link("https://aplnk.to/abc")
    private let foreign = link("https://example.com/abc")

    private func held(_ host: TestHost) -> [ArrivalEntry] {
        host.ledger.slots.map(\.entry)
    }

    // MARK: - Application delegate, no scenes

    func testColdLaunchIsOneLaunchArrivalFromTheFollowUpCall() {
        let host = TestHost()
        host.ingress.applicationDidFinishLaunching(launchURLs: [tap])
        XCTAssertTrue(held(host).isEmpty)
        XCTAssertFalse(host.process.verdict.isDecided)

        XCTAssertTrue(host.ingress.applicationContinue(tap))
        XCTAssertEqual(held(host).map(\.isLaunch), [true])
        XCTAssertEqual(held(host).first?.url, tap)
        XCTAssertTrue(host.process.verdict.isDecided)
    }

    func testLaunchWithoutAURLEndsTheWindowWithNoLaunchArrival() {
        let host = TestHost()
        host.ingress.applicationDidFinishLaunching(launchURLs: [])
        XCTAssertTrue(host.process.verdict.isDecided)
        XCTAssertTrue(held(host).isEmpty)
    }

    func testAWarmDeliveryIsOneNonLaunchArrival() {
        let host = TestHost()
        host.finishLaunch()
        XCTAssertFalse(host.ingress.applicationOpen(link("myapp://x")))
        XCTAssertTrue(host.ingress.applicationContinue(tap))
        XCTAssertEqual(held(host).map(\.isLaunch), [false, false])
        XCTAssertEqual(held(host).map(\.source), [.customScheme, .universalLink])
    }

    func testALaterTapOnTheSameURLIsANewArrival() {
        let host = TestHost()
        host.finishLaunch()
        _ = host.ingress.applicationContinue(tap)
        _ = host.ingress.applicationContinue(tap)
        let entries = held(host)
        XCTAssertEqual(entries.count, 2)
        XCTAssertNotEqual(entries[0].id, entries[1].id)
        XCTAssertLessThan(entries[0].seq, entries[1].seq)
    }

    // MARK: - Scene delegate

    func testSceneConnectionRecordsTheLaunchOnceAndOnlyTheFirstURLIsTheLaunch() {
        let host = TestHost(declaresScenes: true)
        host.ingress.applicationDidFinishLaunching(launchURLs: [])
        XCTAssertFalse(host.process.verdict.isDecided)

        let other = link("https://aplnk.to/other")
        XCTAssertTrue(host.ingress.sceneConnecting(activityURLs: [tap], contextURLs: [other]))
        XCTAssertEqual(held(host).map(\.url), [tap, other])
        XCTAssertEqual(held(host).map(\.isLaunch), [true, false])
        XCTAssertTrue(host.process.verdict.isDecided)
    }

    func testAConnectionWithEmptyOptionsEndsTheLaunchWindow() {
        let host = TestHost(declaresScenes: true)
        XCTAssertFalse(host.ingress.sceneConnecting(activityURLs: [], contextURLs: []))
        XCTAssertTrue(host.process.verdict.isDecided)
        XCTAssertTrue(held(host).isEmpty)
    }

    func testAConnectionWithoutOptionsLeavesTheLaunchWindowOpenUntilActivation() {
        let host = TestHost(declaresScenes: true)
        XCTAssertFalse(host.ingress.sceneConnecting(activityURLs: nil, contextURLs: nil))
        XCTAssertFalse(host.process.verdict.isDecided)
        XCTAssertTrue(held(host).isEmpty)
        host.ingress.becameActive()
        XCTAssertTrue(host.process.verdict.isDecided)
    }

    func testALaterSceneConnectionIsNotALaunch() {
        let host = TestHost(declaresScenes: true)
        _ = host.ingress.sceneConnecting(activityURLs: [], contextURLs: [])
        _ = host.ingress.sceneConnecting(activityURLs: [tap], contextURLs: [])
        XCTAssertEqual(held(host).map(\.isLaunch), [false])
    }

    func testSceneWarmDeliveriesAreOneArrivalEach() {
        let host = TestHost(declaresScenes: true)
        host.finishLaunch()
        XCTAssertTrue(host.ingress.sceneContinue(tap))
        XCTAssertFalse(host.ingress.sceneOpen([link("myapp://x")]))
        XCTAssertEqual(held(host).map(\.source), [.universalLink, .customScheme])
        XCTAssertEqual(held(host).map(\.isLaunch), [false, false])
    }

    // MARK: - One source per delivery

    func testAnAppWithScenesTakesNothingFromTheApplicationDelegate() {
        let host = TestHost(declaresScenes: true)
        host.finishLaunch()
        XCTAssertTrue(host.ingress.applicationOpen(tap))
        XCTAssertTrue(host.ingress.applicationContinue(tap))
        XCTAssertTrue(held(host).isEmpty)
        XCTAssertTrue(host.ingress.sceneOpen([tap]))
        XCTAssertEqual(held(host).count, 1)
    }

    func testOnceASceneDeliveredTheApplicationDelegateIsIgnored() {
        let host = TestHost()
        host.finishLaunch()
        XCTAssertTrue(host.ingress.sceneContinue(tap))
        XCTAssertTrue(host.ingress.applicationContinue(tap))
        XCTAssertTrue(host.ingress.applicationOpen(tap))
        XCTAssertEqual(held(host).count, 1)
    }

    func testAForeignURLFromTheApplicationDelegateIsNotClaimedWhenASceneOwnsIt() {
        let host = TestHost(declaresScenes: true)
        XCTAssertFalse(host.ingress.applicationOpen(foreign))
        XCTAssertTrue(held(host).isEmpty)
    }

    // MARK: - Claims

    func testWarpLinkURLsAreClaimedAndForeignURLsAreNotButBothAreRecorded() {
        let host = TestHost()
        host.finishLaunch()
        XCTAssertTrue(host.ingress.applicationContinue(tap))
        XCTAssertFalse(host.ingress.applicationContinue(foreign))
        XCTAssertEqual(held(host).map(\.url), [tap, foreign])
    }

    func testAnAppSubdomainIsClaimedBeforeConfigure() {
        let host = TestHost()
        host.finishLaunch()
        XCTAssertFalse(host.native.isConfigured)
        XCTAssertTrue(host.ingress.applicationContinue(link("https://acme.aplnk.to/abc")))
    }

    func testAnAppActivationEndsTheLaunchWindow() {
        let host = TestHost()
        host.ingress.becameActive()
        XCTAssertTrue(host.process.verdict.isDecided)
    }
}
