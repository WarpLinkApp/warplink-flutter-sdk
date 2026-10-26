package app.warplink.flutter

import app.warplink.ReferralClaimResult
import app.warplink.WarpLinkError
import app.warplink.referral.EvidenceClass
import app.warplink.referral.MatchMethod
import app.warplink.referral.ReferralClaimStatus
import app.warplink.referral.ReplayState
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The referral handoff channel methods: WL-S40 to WL-S46 on the Flutter plugin. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReferralMethodsTest {
    private val harness = ProcessHarness()
    private val sdk = harness.sdk
    private val engine = harness.newEngine()

    private fun matched() =
        sampleLink("invited").copy(
            isDeferred = true,
            attributionId = "attr-1",
            matchMethod = MatchMethod.INSTALL_TOKEN,
            evidenceClass = EvidenceClass.EXACT,
            replayState = ReplayState.ORIGINAL,
            capturedParams = mapOf("utm_source" to "friend"),
            tappedAt = "2026-10-20T10:00:00Z"
        )

    @Test
    fun `WL-S40 redeem forwards the pasted text untouched`() {
        sdk.redeemOutcome = Result.success(matched())
        val paste = "  Join me: https://acme.aplnk.to/i \n"

        val map = engine.call("redeemInvitation", mapOf("text" to paste)) as Map<*, *>

        assertEquals(listOf(paste), sdk.redeemed)
        assertEquals("invited", map["linkId"])
    }

    @Test
    fun `WL-S41 text that is not an invitation replies null`() {
        assertNull(engine.call("redeemInvitation", mapOf("text" to "hello")))
        assertEquals(listOf("hello"), sdk.redeemed)
    }

    @Test
    fun `WL-S42 a refusal replies the mapped error`() {
        sdk.redeemOutcome = Result.failure(WarpLinkError.NotConfigured)
        sdk.claimOutcome = Result.failure(WarpLinkError.NotConfigured)

        assertEquals("error:E_NOT_CONFIGURED", engine.call("redeemInvitation", mapOf("text" to "x")))
        assertEquals("error:E_NOT_CONFIGURED", engine.call("claimReferral", mapOf("installerId" to "u")))
    }

    @Test
    fun `WL-S43 the match carries the six evidence fields`() {
        val map = matched().toChannelMap()

        assertEquals("attr-1", map["attributionId"])
        assertEquals("install_token", map["matchMethod"])
        assertEquals("exact", map["evidenceClass"])
        assertEquals("original", map["replayState"])
        assertEquals(mapOf("utm_source" to "friend"), map["capturedParams"])
        assertEquals("2026-10-20T10:00:00Z", map["tappedAt"])
        assertEquals(map["attributionId"], matched().toAttributionMap()["attributionId"])
    }

    @Test
    fun `WL-S46 a link id match stays legacy link`() {
        val link = sampleLink().copy(matchMethod = MatchMethod.LINK_OPEN, evidenceClass = EvidenceClass.LEGACY_LINK)

        val map = link.toChannelMap()

        assertEquals("legacy_link", map["evidenceClass"])
        assertEquals("link_open", map["matchMethod"])
    }

    @Test
    fun `WL-S43 an unknown evidence is null`() {
        val map = sampleLink().toAttributionMap()

        assertNull(map["evidenceClass"])
        assertNull(map["attributionId"])
        assertEquals(emptyMap<String, Any?>(), map["capturedParams"])
    }

    @Test
    fun `WL-S45 the claim replies every field`() {
        sdk.claimOutcome =
            Result.success(
                ReferralClaimResult(
                    status = ReferralClaimStatus.FLAGGED,
                    referralId = "ref-1",
                    linkId = "link-1",
                    linkUrl = "https://acme.aplnk.to/i",
                    matchMethod = MatchMethod.PROBABILISTIC,
                    isExact = false,
                    matchConfidence = 0.7,
                    flags = listOf("outside_window"),
                    duplicateOf = null,
                    updated = true,
                    replayState = ReplayState.REPLAYED
                )
            )

        val map = engine.call("claimReferral", mapOf("installerId" to "user-42")) as Map<*, *>

        assertEquals(listOf("user-42"), sdk.claimed)
        assertEquals("flagged", map["status"])
        assertEquals("ref-1", map["referralId"])
        assertEquals("probabilistic", map["matchMethod"])
        assertEquals(false, map["isExact"])
        assertEquals(0.7, map["matchConfidence"])
        assertEquals(listOf("outside_window"), map["flags"])
        assertEquals(true, map["updated"])
        assertEquals("replayed", map["replayState"])
    }

    @Test
    fun `WL-S45 none is an answer not an error`() {
        val map = engine.call("claimReferral", mapOf("installerId" to "user-42")) as Map<*, *>

        assertEquals("none", map["status"])
        assertNull(map["referralId"])
    }

    @Test
    fun `WL-S45 a missing installer id reaches native as an empty string`() {
        engine.call("claimReferral")

        assertEquals(listOf(""), sdk.claimed)
    }

    @Test
    fun `WL-S45 an argument of another type reaches native as an empty string`() {
        engine.call("claimReferral", mapOf("installerId" to 5))
        engine.call("redeemInvitation", mapOf("text" to listOf("x")))

        assertEquals(listOf(""), sdk.claimed)
        assertEquals(listOf(""), sdk.redeemed)
    }
}
