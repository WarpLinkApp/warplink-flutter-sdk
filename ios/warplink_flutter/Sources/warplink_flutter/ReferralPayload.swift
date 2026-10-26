import Foundation
import WarpLink

/// Builds the referral parts of the channel maps (channel contract section 3).
enum ReferralPayload {
    /// The six additive evidence fields of a match. Absent values are null.
    static func evidence(_ link: WarpLinkDeepLink) -> [String: Any] {
        [
            "attributionId": link.attributionId ?? NSNull(),
            "matchMethod": link.matchMethod?.rawValue ?? NSNull(),
            "evidenceClass": link.evidenceClass?.rawValue ?? NSNull(),
            "replayState": link.replayState?.rawValue ?? NSNull(),
            "capturedParams": link.capturedParams.mapValues(DeepLinkPayload.foundationValue),
            "tappedAt": link.tappedAt ?? NSNull(),
        ]
    }

    /// The claim map (section 3.3). Every key is always present.
    static func claim(_ result: ReferralClaimResult) -> [String: Any] {
        [
            "status": result.status.rawValue,
            "referralId": result.referralId ?? NSNull(),
            "linkId": result.linkId ?? NSNull(),
            "linkUrl": result.linkUrl ?? NSNull(),
            "matchMethod": result.matchMethod?.rawValue ?? NSNull(),
            "isExact": result.isExact,
            "matchConfidence": result.matchConfidence ?? NSNull(),
            "flags": result.flags,
            "duplicateOf": result.duplicateOf ?? NSNull(),
            "updated": result.updated,
            "replayState": result.replayState?.rawValue ?? NSNull(),
        ]
    }
}
