import Flutter
import WarpLink
import XCTest

@testable import warplink_flutter

final class MethodDispatchTests: XCTestCase {
    private let rig = PluginRig()

    func testUnknownMethodAnswersNotImplemented() {
        guard case .notImplemented? = rig.call("nope") else {
            return XCTFail("expected notImplemented")
        }
    }

    func testSimpleReadsComeFromNative() {
        rig.native.isConfigured = true
        rig.native.isAttributionComplete = true
        rig.native.sdkVersion = "9.9.9"
        XCTAssertEqual(rig.call("isConfigured").value as? Bool, true)
        XCTAssertEqual(rig.call("isAttributionComplete").value as? Bool, true)
        XCTAssertEqual(rig.call("getSdkVersion").value as? String, "9.9.9")
    }

    func testIsWarpLinkUrlNeverErrors() {
        XCTAssertEqual(isLink("https://aplnk.to/abc"), true)
        XCTAssertEqual(isLink("https://acme.aplnk.to/abc"), true)
        XCTAssertEqual(isLink("https://example.com/abc"), false)
        XCTAssertEqual(isLink("https://aplnk.to/a/b"), false)
        XCTAssertEqual(isLink(""), false)
        XCTAssertEqual(rig.call("isWarpLinkUrl").value as? Bool, false)
    }

    func testHandleDeepLinkReturnsContractMap() throws {
        rig.native.resolveResult = .success(sampleLink())
        let map = try XCTUnwrap(
            rig.call("handleDeepLink", ["url": "https://aplnk.to/abc"]).value as? [String: Any]
        )
        XCTAssertEqual(map["linkId"] as? String, "link-1")
        XCTAssertEqual(map["deepLinkUrl"] as? String, "myapp://p")
        XCTAssertEqual(map["matchType"] as? String, "deterministic")
        XCTAssertEqual(map["matchConfidence"] as? Double, 1.0)
        XCTAssertEqual(map["matchGuaranteed"] as? Bool, true)
        XCTAssertEqual(map["isDeferred"] as? Bool, false)
        let params = try XCTUnwrap(map["customParams"] as? [String: Any])
        XCTAssertEqual(params["n"] as? Int, 3)
        let tags = try XCTUnwrap(params["tags"] as? [Any])
        XCTAssertEqual(tags[0] as? String, "a")
        XCTAssertTrue(tags[1] is NSNull)
    }

    func testHandleDeepLinkWithoutLinkURLFieldsUsesNull() throws {
        rig.native.resolveResult = .success(
            WarpLinkDeepLink(linkId: "x", destination: "https://e.com")
        )
        let map = try XCTUnwrap(
            rig.call("handleDeepLink", ["url": "https://aplnk.to/abc"]).value as? [String: Any]
        )
        XCTAssertTrue(map["deepLinkUrl"] is NSNull)
        XCTAssertTrue(map["matchType"] is NSNull)
        XCTAssertTrue(map["matchConfidence"] is NSNull)
        XCTAssertEqual((map["customParams"] as? [String: Any])?.count, 0)
    }

    func testHandleDeepLinkRejectsUnparsableAndMissingURL() {
        XCTAssertEqual(rig.call("handleDeepLink", ["url": ""]).error?.code, "E_INVALID_URL")
        XCTAssertEqual(rig.call("handleDeepLink").error?.code, "E_INVALID_URL")
    }

    func testHandleDeepLinkPassesNativeErrorThrough() {
        rig.native.resolveResult = .failure(.linkNotFound)
        let error = rig.call("handleDeepLink", ["url": "https://aplnk.to/abc"]).error
        XCTAssertEqual(error?.code, "E_LINK_NOT_FOUND")
        XCTAssertEqual(error?.message, WarpLinkError.linkNotFound.errorDescription)
    }

    func testCheckDeferredDeepLinkAnswersNullForNoMatch() {
        rig.native.deferredResult = .success(nil)
        XCTAssertNil(rig.call("checkDeferredDeepLink").value)
    }

    func testCheckDeferredDeepLinkAnswersMapForMatch() throws {
        rig.native.deferredResult = .success(sampleLink(id: "d"))
        let map = try XCTUnwrap(rig.call("checkDeferredDeepLink").value as? [String: Any])
        XCTAssertEqual(map["linkId"] as? String, "d")
    }

    func testCheckDeferredDeepLinkMapsFailure() {
        rig.native.deferredResult = .failure(.notConfigured)
        XCTAssertEqual(rig.call("checkDeferredDeepLink").error?.code, "E_NOT_CONFIGURED")
    }

    func testAttributionBeforeConfigureIsNotConfigured() {
        XCTAssertEqual(rig.call("getAttributionResult").error?.code, "E_NOT_CONFIGURED")
    }

    func testAttributionNullWhenNoMatch() {
        rig.native.isConfigured = true
        XCTAssertNil(rig.call("getAttributionResult").value)
    }

    func testAttributionMapHoldsOnlyTheContractKeys() throws {
        rig.native.isConfigured = true
        rig.native.attributionResult = sampleLink()
        let map = try XCTUnwrap(rig.call("getAttributionResult").value as? [String: Any])
        XCTAssertEqual(
            Set(map.keys),
            ["linkId", "matchType", "matchConfidence", "matchGuaranteed", "isDeferred"]
        )
        XCTAssertEqual(map["matchType"] as? String, "deterministic")
    }

    private func isLink(_ url: String) -> Bool? {
        rig.call("isWarpLinkUrl", ["url": url]).value as? Bool
    }
}
