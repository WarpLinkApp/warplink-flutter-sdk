package app.warplink.flutter

import app.warplink.WarpLinkError
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The `clearAttribution` channel method: WL-S50 and WL-S52 on the Flutter plugin. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ClearAttributionMethodTest {
    private val harness = ProcessHarness()
    private val sdk = harness.sdk
    private val engine = harness.newEngine()

    @Test
    fun `WL-S50 the call is forwarded to native and replies null`() {
        assertNull(engine.call("clearAttribution"))
        assertEquals(1, sdk.clears)
    }

    @Test
    fun `WL-S50 a refusal before configure replies the mapped error`() {
        sdk.clearOutcome = Result.failure(WarpLinkError.NotConfigured)

        assertEquals("error:E_NOT_CONFIGURED", engine.call("clearAttribution"))
    }

    @Test
    fun `WL-S52 a storage failure replies E_DECODING_ERROR`() {
        sdk.clearOutcome = Result.failure(
            WarpLinkError.DecodingError(IllegalStateException("Could not clear stored attribution data."))
        )

        assertEquals("error:E_DECODING_ERROR", engine.call("clearAttribution"))
    }
}
