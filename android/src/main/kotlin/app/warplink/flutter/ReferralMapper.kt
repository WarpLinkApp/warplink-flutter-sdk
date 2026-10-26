package app.warplink.flutter

import app.warplink.ReferralClaimResult

/**
 * Builds the claim map of the channel contract (section 3.3).
 *
 * The native SDK owns every decision. This only names the fields, and a value
 * it cannot name is sent as null, which Dart reads as its safe default.
 */
fun ReferralClaimResult.toChannelMap(): Map<String, Any?> =
    mapOf(
        "status" to status.wireValue,
        "referralId" to referralId,
        "linkId" to linkId,
        "linkUrl" to linkUrl,
        "matchMethod" to matchMethod?.wireValue,
        "isExact" to isExact,
        "matchConfidence" to matchConfidence,
        "flags" to flags,
        "duplicateOf" to duplicateOf,
        "updated" to updated,
        "replayState" to replayState?.wireValue
    )
