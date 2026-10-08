import Flutter
import WarpLink
import XCTest

@testable import warplink_flutter

final class ConfigureTests: XCTestCase {
    private let rig = PluginRig()

    func testConfigureForwardsArgumentsToNative() throws {
        let reply = rig.call(
            "configure",
            rig.configureArguments([
                "apiEndpoint": "https://api.example.test/v1",
                "debugLogging": true,
                "linkDomains": ["links.example.com", 7, "www.example.org"],
            ])
        )
        guard case .value(nil)? = reply else { return XCTFail("expected a null reply") }
        let call = try XCTUnwrap(rig.native.configureCalls.first)
        XCTAssertEqual(call.apiKey, PluginRig.validKey)
        XCTAssertEqual(call.options.apiEndpoint, "https://api.example.test/v1")
        XCTAssertTrue(call.options.debugLogging)
        XCTAssertEqual(call.options.linkDomains, ["links.example.com", "www.example.org"])
    }

    func testNativeIsAlwaysConfiguredWithBothAutomaticPathsOffAndNoSink() throws {
        _ = rig.call(
            "configure",
            rig.configureArguments([
                "automaticDeepLinks": true,
                "automaticDeferredDeepLinks": true,
                "hasOnLink": true,
                "generation": 4,
            ])
        )
        let options = try XCTUnwrap(rig.native.latestOptions)
        XCTAssertFalse(options.autoDeepLinkHandling)
        XCTAssertFalse(options.autoDeferredCheck)
        XCTAssertNil(options.onLink)
    }

    func testAnIdenticalConfigurationIsAppliedOnceAcrossEngines() {
        _ = rig.call("configure", rig.configureArguments())
        _ = PluginRig(host: rig.host).call("configure", rig.configureArguments())
        _ = rig.call("configure", rig.configureArguments())
        XCTAssertEqual(rig.native.configureCalls.count, 1)
    }

    func testAChangedConfigurationIsAppliedAgain() {
        _ = rig.call("configure", rig.configureArguments())
        _ = rig.call("configure", rig.configureArguments(["debugLogging": true]))
        XCTAssertEqual(rig.native.configureCalls.count, 2)
    }

    func testConfigureKeepsTheLedger() {
        let entry = rig.host.ledger.record(
            url: link("https://aplnk.to/abc"), source: .universalLink, isLaunch: false
        )
        _ = rig.call("configure", rig.configureArguments())
        _ = rig.call("configure", rig.configureArguments(["debugLogging": true]))
        XCTAssertEqual(rig.host.ledger.slots.map(\.entry.id), [entry.id])
    }

    func testBadKeyAnswersInvalidFormatAndSkipsNative() {
        let keys = [
            "nope", "wl_live_short", PluginRig.validKey + "\n",
            "wl_dev_" + String(repeating: "a", count: 32),
        ]
        for key in keys {
            let error = rig.call("configure", rig.configureArguments(["apiKey": key])).error
            XCTAssertEqual(error?.code, "E_INVALID_API_KEY_FORMAT")
            XCTAssertNil(error?.details)
        }
        XCTAssertTrue(rig.native.configureCalls.isEmpty)
    }

    func testABadKeyNeverChangesTheEarlierConfiguration() {
        _ = rig.call("configure", rig.configureArguments())
        _ = rig.call("configure", rig.configureArguments(["apiKey": "nope"]))
        _ = rig.call("configure", rig.configureArguments())
        XCTAssertEqual(rig.native.configureCalls.count, 1)
    }

    func testMissingKeyAnswersInvalidFormat() {
        let error = rig.call("configure", ["debugLogging": true]).error
        XCTAssertEqual(error?.code, "E_INVALID_API_KEY_FORMAT")
        XCTAssertEqual(error?.message, "apiKey is required")
    }
}
