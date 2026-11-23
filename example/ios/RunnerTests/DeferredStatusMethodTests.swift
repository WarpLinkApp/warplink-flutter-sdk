import Flutter
import XCTest

@testable import warplink_flutter
@testable import WarpLink

/// The deferred check status method on the iOS plugin.
final class DeferredStatusMethodTests: XCTestCase {
    private let rig = PluginRig()

    // WL-S74
    func testWLS74EachStateWithoutAWaitRepliesItsNameAlone() throws {
        let expected: [(DeferredCheckStatus, String)] = [
            (.notChecked, "notChecked"),
            (.checking, "checking"),
            (.matched, "matched"),
            (.noMatch, "noMatch"),
            (.skippedOldInstall, "skippedOldInstall"),
            (.stopped, "stopped"),
        ]
        for (status, name) in expected {
            rig.native.deferredCheckStatus = status

            let map = try XCTUnwrap(rig.call("getDeferredCheckStatus").value as? [String: Any])

            XCTAssertEqual(map["state"] as? String, name)
            XCTAssertEqual(map.count, 1)
        }
    }

    // WL-S74
    func testWLS74WaitingRepliesTheRetryTimeInEpochMilliseconds() throws {
        rig.native.deferredCheckStatus = .waiting(retryAt: Date(timeIntervalSince1970: 1_800_000_000.25))

        let map = try XCTUnwrap(rig.call("getDeferredCheckStatus").value as? [String: Any])

        XCTAssertEqual(map["state"] as? String, "waiting")
        XCTAssertEqual(map["retryAt"] as? Int, 1_800_000_000_250)
    }

    func testReadingTheStatusStartsNoCheck() {
        _ = rig.call("getDeferredCheckStatus")

        XCTAssertTrue(rig.native.resolveCalls.isEmpty)
    }
}
