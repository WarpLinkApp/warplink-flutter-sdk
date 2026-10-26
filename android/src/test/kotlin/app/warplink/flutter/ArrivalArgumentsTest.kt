package app.warplink.flutter

import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/** An arrival id of the wrong type is an id the ledger does not hold, never a thrown cast. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ArrivalArgumentsTest {
    private val harness = ProcessHarness()
    private val engine = harness.newEngine()

    @Test
    fun `resolveArrival with a non-string arrival id replies null without a native call`() {
        assertNull(engine.call("resolveArrival", mapOf("arrivalId" to 42)))
        assertEquals(emptyList(), harness.sdk.handled)
    }

    @Test
    fun `resolveArrival without an arrival id replies null without a native call`() {
        assertNull(engine.call("resolveArrival", emptyMap()))
        assertEquals(emptyList(), harness.sdk.handled)
    }

    @Test
    fun `claimDelivery with a non-string arrival id replies false`() {
        assertFalse(engine.call("claimDelivery", mapOf("arrivalId" to 42)) as Boolean)
    }
}
