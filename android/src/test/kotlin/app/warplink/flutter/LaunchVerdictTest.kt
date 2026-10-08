package app.warplink.flutter

import android.content.Intent
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** `getPendingArrivals` waits for the fresh-launch verdict (contract section 4.3). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LaunchVerdictTest {
    private val harness = ProcessHarness()
    private val engine = harness.newEngine()

    @Test
    fun aPrewarmedEngineWaitsForAnActivityBeforeItAnswers() {
        engine.configure()
        val reply = engine.callAsync("getPendingArrivals")
        assertFalse(reply.answered)

        engine.launchActivity(viewIntent(COLD))

        assertTrue(reply.answered)
        assertEquals(COLD, (reply.value as List<*>).map { (it as Map<*, *>)["url"] }.single())
    }

    @Test
    fun aFreshLaunchWithoutALinkAnswersWithAnEmptyList() {
        val reply = engine.callAsync("getPendingArrivals")
        engine.launchActivity(Intent(Intent.ACTION_MAIN))
        assertTrue(reply.answered)
        assertEquals(emptyList<Any?>(), reply.value)
    }

    @Test
    fun aRestoredFirstActivityEndsTheWaitWithAnEmptyList() {
        engine.launchActivity(viewIntent(COLD))
        val saved = engine.activityBinding.save()

        val afterProcessDeath = ProcessHarness().newEngine()
        val reply = afterProcessDeath.callAsync("getPendingArrivals")
        assertFalse(reply.answered)
        afterProcessDeath.launchActivity(viewIntent(COLD), saved)

        assertTrue(reply.answered)
        assertEquals(emptyList<Any?>(), reply.value)
    }

    @Test
    fun theVerdictHoldsForASecondEngineOfTheProcess() {
        engine.launchActivity(viewIntent(COLD))

        val second = harness.newEngine()
        val reply = second.callAsync("getPendingArrivals")

        assertTrue(reply.answered)
        assertEquals(listOf(COLD), (reply.value as List<*>).map { (it as Map<*, *>)["url"] })
    }

    private companion object {
        const val COLD = "https://aplnk.to/cold"
    }
}
