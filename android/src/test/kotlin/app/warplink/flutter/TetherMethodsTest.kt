package app.warplink.flutter

import app.warplink.WarpLinkError
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The Tether handoff channel methods on the Android plugin: WL-S53, WL-S56, WL-S61. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TetherMethodsTest {
    private val harness = ProcessHarness()
    private val sdk = harness.sdk
    private val engine = harness.newEngine()

    @Test
    fun `WL-S56 a read replies no code with no reason and never a link`() {
        val map = engine.call("readTether") as Map<*, *>

        assertEquals(1, sdk.tetherReads)
        assertEquals("noCode", map["kind"])
        assertEquals(true, map.containsKey("reason"))
        assertNull(map["reason"])
        assertNull(map["link"])
    }

    @Test
    fun `a read before configure replies the mapped error`() {
        sdk.tetherOutcome = Result.failure(WarpLinkError.NotConfigured)

        assertEquals("error:E_NOT_CONFIGURED", engine.call("readTether"))
    }

    @Test
    fun `WL-S61 the test receipt is read from native`() {
        assertNull(engine.call("getTetherTestReceipt"))

        sdk.lastTetherTestReceipt = "rcpt-1"

        assertEquals("rcpt-1", engine.call("getTetherTestReceipt"))
    }

    @Test
    fun `the paste button is never supported on Android`() {
        assertEquals(false, engine.call("isPasteButtonSupported"))
    }

    @Test
    fun `WL-S53 a read mode in configure is accepted and does not reach native`() {
        engine.call("configure", mapOf("apiKey" to VALID_KEY, "tetherReadMode" to "automatic"))

        assertEquals(1, sdk.configures.size)
        assertEquals(0, sdk.tetherReads)
    }
}
