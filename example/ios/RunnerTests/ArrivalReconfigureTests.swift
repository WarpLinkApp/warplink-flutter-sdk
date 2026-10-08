import Flutter
import XCTest

@testable import warplink_flutter

/// A native `configure` never cancels a manual resolve, so the ledger discards
/// an answer that settles under an older configuration and resolves again.
final class ArrivalReconfigureTests: XCTestCase {
    private let host = TestHost()
    private lazy var rig = PluginRig(host: host)
    private var replies: [String?] = []

    private func startResolve() -> String {
        let id = host.ledger.record(
            url: link("https://aplnk.to/abc"), source: .universalLink, isLaunch: false
        ).id
        rig.methods.handle(FlutterMethodCall(methodName: "resolveArrival", arguments: ["arrivalId": id])) {
            [self] value in
            replies.append((value as? [String: Any])?["linkId"] as? String)
        }
        return id
    }

    func testAChangedConfigureResolvesAgainUnderTheNewConfiguration() {
        host.native.holdResolves = true
        _ = rig.call("configure", rig.configureArguments())
        _ = startResolve()

        _ = rig.call("configure", rig.configureArguments(["debugLogging": true]))
        host.native.finishHeldResolve(.success(sampleLink(id: "old")))
        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(host.native.resolveCalls.count, 2)

        host.native.finishHeldResolve(.success(sampleLink(id: "new")))
        XCTAssertEqual(replies, ["new"])
        XCTAssertEqual(host.native.resolveCalls.count, 2)
    }

    func testAnIdenticalConfigureKeepsTheResolveInFlight() {
        host.native.holdResolves = true
        _ = rig.call("configure", rig.configureArguments())
        _ = startResolve()

        _ = rig.call("configure", rig.configureArguments())
        host.native.finishHeldResolve(.success(sampleLink(id: "kept")))
        XCTAssertEqual(replies, ["kept"])
        XCTAssertEqual(host.native.resolveCalls.count, 1)
    }

    func testAResolveStartedAfterTheChangeIsKept() {
        host.native.holdResolves = true
        _ = rig.call("configure", rig.configureArguments())
        _ = rig.call("configure", rig.configureArguments(["debugLogging": true]))
        _ = startResolve()

        host.native.finishHeldResolve(.success(sampleLink(id: "current")))
        XCTAssertEqual(replies, ["current"])
        XCTAssertEqual(host.native.resolveCalls.count, 1)
    }

    func testAJoinedWaiterGetsTheAnswerOfTheRestartedResolve() {
        host.native.holdResolves = true
        _ = rig.call("configure", rig.configureArguments())
        let id = startResolve()
        rig.methods.handle(FlutterMethodCall(methodName: "resolveArrival", arguments: ["arrivalId": id])) {
            [self] value in
            replies.append((value as? [String: Any])?["linkId"] as? String)
        }

        _ = rig.call("configure", rig.configureArguments(["debugLogging": true]))
        host.native.finishHeldResolve(.success(sampleLink(id: "old")))
        host.native.finishHeldResolve(.success(sampleLink(id: "new")))
        XCTAssertEqual(replies, ["new", "new"])
        XCTAssertEqual(host.native.resolveCalls.count, 2)
    }
}
