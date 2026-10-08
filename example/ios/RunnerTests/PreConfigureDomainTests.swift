import Flutter
import UIKit
import WarpLink
import XCTest

@testable import warplink_flutter

/// Classification of arrivals that land before `configure`.
final class PreConfigureDomainTests: XCTestCase {
    private let custom = link("https://Links.Example.com/abc")

    // conformance: WL-S08
    func testADeclaredCustomDomainIsClaimedBeforeConfigure() {
        let host = TestHost(declaredDomains: ["https://links.example.com/"])
        host.finishLaunch()
        XCTAssertFalse(host.native.isConfigured)
        XCTAssertTrue(host.ingress.applicationContinue(custom))
    }

    // conformance: WL-S08
    func testAnUndeclaredCustomDomainIsNotClaimed() {
        let host = TestHost()
        host.finishLaunch()
        XCTAssertFalse(host.ingress.applicationContinue(custom))
        XCTAssertEqual(host.ledger.slots.count, 1)
    }

    // conformance: WL-S08
    func testIsWarpLinkUrlUsesTheSameClassifierBeforeConfigure() {
        let rig = PluginRig(host: TestHost(declaredDomains: ["links.example.com"]))
        XCTAssertEqual(
            rig.call("isWarpLinkUrl", ["url": custom.absoluteString]).value as? Bool, true
        )
    }

    func testMatcherAppliesNativeHostAndPathRules() {
        let matcher = PreConfigureLinkMatcher(declared: { "a.example.com, B.example.com:8443" })
        let yes = [
            "https://aplnk.to/abc", "https://APLNK.to/abc", "https://a.example.com/s",
            "https://b.example.com/s",
        ]
        let no = [
            "https://aplnk.to/", "https://aplnk.to/a/b", "https://example.com/abc",
            "https://c.example.com/abc",
        ]
        yes.forEach { XCTAssertTrue(matcher.matches(link($0)), $0) }
        no.forEach { XCTAssertFalse(matcher.matches(link($0)), $0) }
    }

    func testEveryAppLinkHostCountsAsWarpLink() {
        let matcher = PreConfigureLinkMatcher(declared: { nil })
        let yes = [
            "https://acme.aplnk.to/abc", "https://ACME.aplnk.to/abc", "https://my-app.aplnk.to/x",
        ]
        let no = [
            "https://acme.aplnk.to/", "https://acme.aplnk.to/a/b", "https://a.b.aplnk.to/abc",
            "https://.aplnk.to/abc", "https://acme.aplnk.to.evil.com/abc",
            "https://notaplnk.to/abc", "https://acme.example.com/abc",
        ]
        yes.forEach { XCTAssertTrue(matcher.matches(link($0)), $0) }
        no.forEach { XCTAssertFalse(matcher.matches(link($0)), $0) }
    }

    func testMatcherIgnoresMalformedDeclarations() {
        let matcher = PreConfigureLinkMatcher(declared: { [true, 3, "ok.example.com"] as [Any] })
        XCTAssertTrue(matcher.matches(link("https://ok.example.com/a")))
        XCTAssertFalse(
            PreConfigureLinkMatcher(declared: { 5 }).matches(link("https://x.com/a"))
        )
    }
}
