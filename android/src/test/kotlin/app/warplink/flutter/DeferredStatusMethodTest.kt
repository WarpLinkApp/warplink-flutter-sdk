package app.warplink.flutter

import app.warplink.DeferredCheckStatus
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals

/** The deferred check status method on the Android plugin. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DeferredStatusMethodTest {
    private val harness = ProcessHarness()
    private val sdk = harness.sdk
    private val engine = harness.newEngine()

    @Test
    fun `WL-S74 each state without a wait replies its name alone`() {
        val expected = mapOf(
            DeferredCheckStatus.NotChecked to "notChecked",
            DeferredCheckStatus.Checking to "checking",
            DeferredCheckStatus.Matched to "matched",
            DeferredCheckStatus.NoMatch to "noMatch",
            DeferredCheckStatus.SkippedOldInstall to "skippedOldInstall",
            DeferredCheckStatus.Stopped to "stopped"
        )

        for ((status, name) in expected) {
            sdk.deferredCheckStatus = status

            assertEquals(mapOf("state" to name), engine.call("getDeferredCheckStatus"))
        }
    }

    @Test
    fun `WL-S74 waiting replies the retry time in epoch milliseconds`() {
        sdk.deferredCheckStatus = DeferredCheckStatus.Waiting(1_800_000_000_000L)

        assertEquals(
            mapOf("state" to "waiting", "retryAt" to 1_800_000_000_000L),
            engine.call("getDeferredCheckStatus")
        )
    }

    @Test
    fun `reading the status calls no check`() {
        engine.call("getDeferredCheckStatus")

        assertEquals(0, sdk.deferredChecks)
    }
}
