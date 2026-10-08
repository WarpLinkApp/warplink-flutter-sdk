import Flutter
import XCTest

@testable import warplink_flutter

final class ArrivalResolveTests: XCTestCase {
    private let host = TestHost()
    private lazy var rig = PluginRig(host: host)

    private func arrive(_ text: String = "https://aplnk.to/abc") -> String {
        host.ledger.record(url: link(text), source: .universalLink, isLaunch: false).id
    }

    private func resolve(_ id: String, on engine: PluginRig? = nil) -> Reply? {
        (engine ?? rig).call("resolveArrival", ["arrivalId": id])
    }

    private func linkId(_ reply: Reply?) -> String? {
        (reply.value as? [String: Any])?["linkId"] as? String
    }

    func testTheFirstResolveCallsNativeOnceWithTheArrivalURL() {
        host.native.resolveResult = .success(sampleLink())
        let id = arrive()
        XCTAssertEqual(linkId(resolve(id)), "link-1")
        XCTAssertEqual(host.native.resolveCalls, [link("https://aplnk.to/abc")])
    }

    func testResolvesInFlightJoinOneNativeRequest() {
        host.native.holdResolves = true
        let id = arrive()
        var replies: [Reply?] = []
        for _ in 0..<3 {
            rig.methods.handle(FlutterMethodCall(methodName: "resolveArrival", arguments: ["arrivalId": id])) {
                replies.append(.value($0))
            }
        }
        XCTAssertEqual(host.native.resolveCalls.count, 1)
        XCTAssertTrue(replies.isEmpty)
        host.native.finishHeldResolve(.success(sampleLink(id: "joined")))
        XCTAssertEqual(replies.count, 3)
        XCTAssertEqual(Set(replies.map(linkId)), ["joined"])
    }

    func testALaterResolveReadsTheStoredAnswer() {
        host.native.resolveResult = .success(sampleLink(id: "stored"))
        let id = arrive()
        _ = resolve(id)
        host.native.resolveResult = .success(sampleLink(id: "other"))
        XCTAssertEqual(linkId(resolve(id)), "stored")
        XCTAssertEqual(host.native.resolveCalls.count, 1)
    }

    func testAFailedResolveRepliesTheSameErrorEveryTime() {
        host.native.resolveResult = .failure(.serverError(statusCode: 503, message: "down"))
        let id = arrive()
        for _ in 0..<2 {
            let error = resolve(id).error
            XCTAssertEqual(error?.code, "E_SERVER_ERROR")
            XCTAssertEqual(error?.details as? [String: Int], ["statusCode": 503])
        }
        XCTAssertEqual(host.native.resolveCalls.count, 1)
    }

    func testANoMatchIsStoredToo() {
        let id = arrive()
        host.native.resolveResult = .failure(.linkNotFound)
        XCTAssertEqual(resolve(id).error?.code, "E_LINK_NOT_FOUND")
        XCTAssertEqual(resolve(id).error?.code, "E_LINK_NOT_FOUND")
        XCTAssertEqual(host.native.resolveCalls.count, 1)
    }

    func testAnUnknownIdAnswersNullWithoutCallingNative() {
        XCTAssertNil(resolve("never-recorded").value)
        XCTAssertNil(rig.call("resolveArrival").value)
        XCTAssertTrue(host.native.resolveCalls.isEmpty)
    }

    func testAnEngineRestartKeepsPendingAndSettledEntries() {
        host.finishLaunch()
        host.native.resolveResult = .success(sampleLink(id: "settled"))
        let settled = arrive("https://aplnk.to/one")
        let pending = arrive("https://aplnk.to/two")
        _ = resolve(settled)

        let restarted = PluginRig(host: host)
        let listed = restarted.call("getPendingArrivals").value as? [[String: Any]]
        XCTAssertEqual(listed?.compactMap { $0["arrivalId"] as? String }, [settled, pending])
        XCTAssertEqual(linkId(resolve(settled, on: restarted)), "settled")
        XCTAssertEqual(host.native.resolveCalls.count, 1)
    }

    func testASettledAnswerSurvivesTheEngineThatAskedDetaching() {
        host.native.holdResolves = true
        let id = arrive()
        rig.methods.handle(FlutterMethodCall(methodName: "resolveArrival", arguments: ["arrivalId": id])) { _ in }
        rig.arrivals.invalidate()
        host.native.finishHeldResolve(.success(sampleLink(id: "late")))

        let next = PluginRig(host: host)
        XCTAssertEqual(linkId(resolve(id, on: next)), "late")
        XCTAssertEqual(host.native.resolveCalls.count, 1)
    }

    func testAClaimDuringTheResolveLetsItFinishAndKeepsTheEntryOutOfTheReplay() {
        host.finishLaunch()
        host.native.holdResolves = true
        let id = arrive()
        var answered = false
        rig.methods.handle(FlutterMethodCall(methodName: "resolveArrival", arguments: ["arrivalId": id])) { _ in
            answered = true
        }
        XCTAssertEqual(rig.call("claimDelivery", ["arrivalId": id]).value as? Bool, true)
        host.native.finishHeldResolve(.success(sampleLink()))
        XCTAssertTrue(answered)
        XCTAssertEqual((rig.call("getPendingArrivals").value as? [Any])?.count, 0)
    }

    func testClaimDeliveryAnswersTrueOnceThroughTheChannel() {
        let id = arrive()
        XCTAssertEqual(rig.call("claimDelivery", ["arrivalId": id]).value as? Bool, true)
        XCTAssertEqual(PluginRig(host: host).call("claimDelivery", ["arrivalId": id]).value as? Bool, false)
        XCTAssertEqual(rig.call("claimDelivery", ["arrivalId": "unknown"]).value as? Bool, false)
        XCTAssertEqual(rig.call("claimDelivery").value as? Bool, false)
    }

    func testAManualHandleDeepLinkIsItsOwnNativeRequest() {
        host.native.resolveResult = .success(sampleLink())
        let id = arrive()
        _ = resolve(id)
        _ = rig.call("handleDeepLink", ["url": "https://aplnk.to/abc"])
        XCTAssertEqual(host.native.resolveCalls.count, 2)
    }
}
