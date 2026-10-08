import Flutter
import XCTest

@testable import warplink_flutter

final class ArrivalsChannelTests: XCTestCase {
    private let host = TestHost()
    private lazy var rig = PluginRig(host: host)

    private func arrive(_ text: String = "https://aplnk.to/abc") {
        host.ledger.record(url: link(text), source: .universalLink, isLaunch: false)
    }

    func testTheFirstEventAfterListenIsReady() {
        arrive()
        let recorder = rig.listen()
        XCTAssertEqual(recorder.maps.count, 1)
        XCTAssertEqual(recorder.maps.first?["type"] as? String, "ready")
        XCTAssertEqual(recorder.maps.first?.count, 1)
    }

    func testEntriesRecordedBeforeListeningAreReplayedNotAnnounced() {
        arrive()
        host.finishLaunch()
        let recorder = rig.listen()
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual((rig.call("getPendingArrivals").value as? [Any])?.count, 1)
    }

    func testEveryEntryRecordedAfterReadyIsOneEventWithRisingSeq() {
        let recorder = rig.listen()
        arrive("https://aplnk.to/a")
        arrive("https://aplnk.to/b")
        let entries = recorder.maps.dropFirst()
        XCTAssertEqual(entries.compactMap { $0["seq"] as? Int }, [0, 1])
        XCTAssertEqual(entries.compactMap { $0["url"] as? String },
                       ["https://aplnk.to/a", "https://aplnk.to/b"])
        XCTAssertNil(entries.first?["type"])
    }

    func testASecondListenReplacesTheSinkAndSignalsReadyAgain() {
        let first = rig.listen()
        let second = rig.listen()
        arrive()
        XCTAssertEqual(first.events.count, 1)
        XCTAssertEqual(second.events.count, 2)
        XCTAssertEqual(second.maps.first?["type"] as? String, "ready")
    }

    func testCancelAndDetachStopTheEvents() {
        let cancelled = rig.listen()
        _ = rig.arrivals.onCancel(withArguments: nil)
        arrive()
        XCTAssertEqual(cancelled.events.count, 1)

        let detached = PluginRig(host: host)
        let recorder = detached.listen()
        detached.arrivals.invalidate()
        arrive()
        XCTAssertEqual(recorder.events.count, 1)
    }

    func testEveryListeningEngineHearsTheEntry() {
        let other = PluginRig(host: host)
        let first = rig.listen()
        let second = other.listen()
        arrive()
        XCTAssertEqual(first.events.count, 2)
        XCTAssertEqual(second.events.count, 2)
    }

    func testGetPendingArrivalsWaitsForTheLaunchVerdict() {
        var replied: [[String: Any]]?
        rig.methods.handle(FlutterMethodCall(methodName: "getPendingArrivals", arguments: nil)) {
            replied = $0 as? [[String: Any]]
        }
        XCTAssertNil(replied)

        host.ingress.applicationDidFinishLaunching(launchURLs: [link("https://aplnk.to/launch")])
        XCTAssertNil(replied)
        _ = host.ingress.applicationContinue(link("https://aplnk.to/launch"))

        XCTAssertEqual(replied?.count, 1)
        XCTAssertEqual(replied?.first?["isLaunch"] as? Bool, true)
    }

    func testTheVerdictHoldsForALaterEngine() {
        host.finishLaunch()
        arrive()
        let later = PluginRig(host: host)
        XCTAssertEqual((later.call("getPendingArrivals").value as? [Any])?.count, 1)
    }

    func testTheRemovedLinksAndUrlsMethodsAreNotImplemented() {
        for method in ["getInitialUrl", "ackArrival"] {
            guard case .notImplemented? = rig.call(method) else {
                return XCTFail("\(method) should not be implemented")
            }
        }
    }
}
