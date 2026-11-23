import Flutter
import XCTest

@testable import warplink_flutter
@testable import WarpLink

/// The Tether handoff channel methods on the iOS plugin.
final class TetherMethodTests: XCTestCase {
    private let rig = PluginRig()

    // WL-S53
    func testWLS53ReadTetherRepliesTheMatchedLink() throws {
        rig.native.tetherResult = .success(.matched(sampleLink(id: "tethered")))

        let map = try XCTUnwrap(rig.call("readTether").value as? [String: Any])

        XCTAssertEqual(rig.native.tetherReads, 1)
        XCTAssertEqual(map["kind"] as? String, "matched")
        let link = try XCTUnwrap(map["link"] as? [String: Any])
        XCTAssertEqual(link["linkId"] as? String, "tethered")
    }

    // WL-S59
    func testWLS59ANoCodeReplyCarriesTheWireReason() throws {
        let reasons: [TetherMissReason] = [.pasteNotAllowed, .clipboardEmpty, .olderSdk]
        for reason in reasons {
            rig.native.tetherResult = .success(.noCode(reason))
            let map = try XCTUnwrap(rig.call("readTether").value as? [String: Any])
            XCTAssertEqual(map["kind"] as? String, "noCode")
            XCTAssertEqual(map["reason"] as? String, reason.rawValue)
        }
    }

    // WL-S61
    func testWLS61ATestCodeRepliesTheReceipt() throws {
        rig.native.tetherResult = .success(.test(receipt: "rcpt-1"))
        let map = try XCTUnwrap(rig.call("readTether").value as? [String: Any])
        XCTAssertEqual(map["kind"] as? String, "test")
        XCTAssertEqual(map["receipt"] as? String, "rcpt-1")
    }

    func testATestCodeWithoutAReceiptRepliesNull() throws {
        rig.native.tetherResult = .success(.test(receipt: nil))
        let map = try XCTUnwrap(rig.call("readTether").value as? [String: Any])
        XCTAssertTrue(map["receipt"] is NSNull)
    }

    // WL-S60
    func testAnUnusableCodeRepliesTheKindOnly() throws {
        rig.native.tetherResult = .success(.unusable)
        let map = try XCTUnwrap(rig.call("readTether").value as? [String: Any])
        XCTAssertEqual(map["kind"] as? String, "unusable")
        XCTAssertNil(map["link"])
    }

    // WL-S60
    func testAFailedReadRepliesTheMappedError() {
        rig.native.tetherResult = .failure(.notConfigured)
        let error = rig.call("readTether").error
        XCTAssertEqual(error?.code, "E_NOT_CONFIGURED")
        XCTAssertEqual(error?.message, WarpLinkError.notConfigured.errorDescription)
    }

    // WL-S61
    func testWLS61TheTestReceiptIsReadFromNative() {
        XCTAssertNil(rig.call("getTetherTestReceipt").value)
        rig.native.lastTetherTestReceipt = "rcpt-2"
        XCTAssertEqual(rig.call("getTetherTestReceipt").value as? String, "rcpt-2")
    }

    // WL-S57
    func testThePasteButtonIsSupportedOnIOS16() {
        if #available(iOS 16.0, *) {
            XCTAssertEqual(rig.call("isPasteButtonSupported").value as? Bool, true)
        } else {
            XCTAssertEqual(rig.call("isPasteButtonSupported").value as? Bool, false)
        }
    }

    // WL-S53
    func testWLS53TheDefaultReadModeIsThePasteButton() throws {
        _ = rig.call("configure", rig.configureArguments())
        let options = try XCTUnwrap(rig.native.latestOptions)
        XCTAssertEqual(options.tetherReadMode, .pasteButton)
    }

    func testEveryWireModeReachesNative() throws {
        for mode in TetherReadMode.allCases {
            _ = rig.call("configure", rig.configureArguments(["tetherReadMode": mode.rawValue]))
            XCTAssertEqual(try XCTUnwrap(rig.native.latestOptions).tetherReadMode, mode)
        }
    }

    func testAnUnknownReadModeFallsBackToThePasteButton() throws {
        _ = rig.call("configure", rig.configureArguments(["tetherReadMode": "onCall"]))
        XCTAssertEqual(try XCTUnwrap(rig.native.latestOptions).tetherReadMode, .pasteButton)
    }

    func testAChangedReadModeIsAppliedAgain() {
        _ = rig.call("configure", rig.configureArguments())
        _ = rig.call("configure", rig.configureArguments(["tetherReadMode": "automatic"]))
        XCTAssertEqual(rig.native.configureCalls.count, 2)
    }

    func testTheEventBodyTellsAnOutcomeFromAFailure() throws {
        let outcome = TetherPayload.eventBody(.success(.unusable))
        let result = try XCTUnwrap(outcome["result"] as? [String: Any])
        XCTAssertEqual(result["kind"] as? String, "unusable")
        XCTAssertNil(outcome["error"])

        let failure = TetherPayload.eventBody(.failure(.networkError(URLError(.timedOut))))
        let error = try XCTUnwrap(failure["error"] as? [String: String])
        XCTAssertEqual(error["code"], "E_NETWORK_ERROR")
        XCTAssertNil(failure["result"])
    }

    @available(iOS 16.0, *)
    func testThePasteStyleReadsArgbColorsAndNames() {
        let style = PasteButtonStyle(arguments: [
            "baseBackgroundColor": 0xFF00_80FF,
            "cornerStyle": "capsule",
            "displayMode": "iconOnly",
        ])
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        style.background?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0, accuracy: 0.01)
        XCTAssertEqual(green, 128.0 / 255, accuracy: 0.01)
        XCTAssertEqual(blue, 1, accuracy: 0.01)
        XCTAssertEqual(alpha, 1, accuracy: 0.01)
        XCTAssertNil(style.foreground)
        XCTAssertEqual(style.cornerStyle, .capsule)
        XCTAssertEqual(style.displayMode, .iconOnly)
    }

    @available(iOS 16.0, *)
    func testAnUnknownPasteStyleNameKeepsTheSystemDefault() {
        let style = PasteButtonStyle(arguments: ["cornerStyle": "round", "displayMode": 7])
        XCTAssertEqual(style.cornerStyle, .dynamic)
        XCTAssertEqual(style.displayMode, .iconAndLabel)
    }
}
