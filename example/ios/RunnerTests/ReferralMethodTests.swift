import Flutter
import XCTest

@testable import warplink_flutter
@testable import WarpLink

/// The referral handoff channel methods on the iOS plugin.
final class ReferralMethodTests: XCTestCase {
    private let rig = PluginRig()

    private func matched() -> WarpLinkDeepLink {
        WarpLinkDeepLink(
            linkId: "invited",
            destination: "https://example.com/i",
            isDeferred: true,
            attributionId: "attr-1",
            matchMethod: .installToken,
            evidenceClass: .exact,
            replayState: .original,
            capturedParams: ["utm_source": .string("friend")],
            tappedAt: "2026-10-20T10:00:00Z"
        )
    }

    // WL-S40
    func testWLS40RedeemForwardsThePastedTextUntouched() throws {
        rig.native.redeemResult = .success(matched())
        let paste = "  Join me: https://acme.aplnk.to/i \n"

        let map = try XCTUnwrap(rig.call("redeemInvitation", ["text": paste]).value as? [String: Any])

        XCTAssertEqual(rig.native.redeemCalls, [paste])
        XCTAssertEqual(map["linkId"] as? String, "invited")
    }

    // WL-S41
    func testWLS41TextThatIsNotAnInvitationRepliesNull() {
        XCTAssertNil(rig.call("redeemInvitation", ["text": "hello"]).value)
        XCTAssertEqual(rig.native.redeemCalls, ["hello"])
    }

    // WL-S42
    func testWLS42ARefusalRepliesTheMappedError() {
        let refusal = WarpLinkError.serverError(statusCode: 400, message: "Open the link again")
        rig.native.redeemResult = .failure(refusal)
        rig.native.claimResult = .failure(refusal)

        let redeemed = rig.call("redeemInvitation", ["text": "x"]).error
        let claimed = rig.call("claimReferral", ["installerId": "u"]).error

        for error in [redeemed, claimed] {
            XCTAssertEqual(error?.code, "E_SERVER_ERROR")
            XCTAssertEqual(error?.message, refusal.errorDescription)
            XCTAssertEqual(error?.details as? [String: Int], ["statusCode": 400])
        }
    }

    // WL-S43
    func testWLS43TheMatchCarriesTheSixEvidenceFields() throws {
        rig.native.resolveResult = .success(matched())
        let map = try XCTUnwrap(
            rig.call("handleDeepLink", ["url": "https://aplnk.to/abc"]).value as? [String: Any]
        )

        XCTAssertEqual(map["attributionId"] as? String, "attr-1")
        XCTAssertEqual(map["matchMethod"] as? String, "install_token")
        XCTAssertEqual(map["evidenceClass"] as? String, "exact")
        XCTAssertEqual(map["replayState"] as? String, "original")
        XCTAssertEqual((map["capturedParams"] as? [String: Any])?["utm_source"] as? String, "friend")
        XCTAssertEqual(map["tappedAt"] as? String, "2026-10-20T10:00:00Z")
    }

    // WL-S43
    func testWLS43AnUnknownEvidenceIsNullInBothMaps() throws {
        rig.native.isConfigured = true
        rig.native.attributionResult = sampleLink()
        let map = try XCTUnwrap(rig.call("getAttributionResult").value as? [String: Any])

        XCTAssertTrue(map["attributionId"] is NSNull)
        XCTAssertTrue(map["evidenceClass"] is NSNull)
        XCTAssertEqual((map["capturedParams"] as? [String: Any])?.count, 0)
    }

    // WL-S45
    func testWLS45TheClaimRepliesEveryField() throws {
        rig.native.claimResult = .success(
            ReferralClaimResult(
                status: .flagged,
                referralId: "ref-1",
                linkId: "link-1",
                linkUrl: "https://acme.aplnk.to/i",
                matchMethod: .probabilistic,
                isExact: false,
                matchConfidence: 0.7,
                flags: ["outside_window"],
                updated: true,
                replayState: .replayed
            )
        )

        let map = try XCTUnwrap(
            rig.call("claimReferral", ["installerId": "user-42"]).value as? [String: Any]
        )

        XCTAssertEqual(rig.native.claimCalls, ["user-42"])
        XCTAssertEqual(map["status"] as? String, "flagged")
        XCTAssertEqual(map["referralId"] as? String, "ref-1")
        XCTAssertEqual(map["matchMethod"] as? String, "probabilistic")
        XCTAssertEqual(map["isExact"] as? Bool, false)
        XCTAssertEqual(map["matchConfidence"] as? Double, 0.7)
        XCTAssertEqual(map["flags"] as? [String], ["outside_window"])
        XCTAssertTrue(map["duplicateOf"] is NSNull)
        XCTAssertEqual(map["updated"] as? Bool, true)
        XCTAssertEqual(map["replayState"] as? String, "replayed")
    }

    // WL-S45
    func testWLS45NoneIsAnAnswerNotAnError() throws {
        let map = try XCTUnwrap(
            rig.call("claimReferral", ["installerId": "user-42"]).value as? [String: Any]
        )

        XCTAssertEqual(map["status"] as? String, "none")
        XCTAssertTrue(map["referralId"] is NSNull)
    }
}
