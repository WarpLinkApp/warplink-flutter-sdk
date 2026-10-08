package app.warplink.flutter

import android.content.Intent
import android.os.Bundle
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Drives the real plugin through Activity launch paths and counts arrivals and native calls. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LaunchLifecycleTest {
    private val harness = ProcessHarness()
    private val engine = harness.newEngine()

    private fun urls(entries: List<Map<*, *>>) = entries.map { it["url"] }

    @Test
    fun aColdTapRecordsOneLaunchArrivalAndCallsNothing() {
        harness.clock.now = 42
        engine.listen()

        engine.launchActivity(viewIntent(COLD))

        val entry = engine.pending().single()
        assertEquals(COLD, entry["url"])
        assertEquals(true, entry["isLaunch"])
        assertEquals(0L, entry["seq"])
        assertEquals("app_link", entry["source"])
        assertEquals(42L, entry["arrivedAtMs"])
        assertEquals(emptyList(), harness.sdk.handled)
        assertEquals(emptyList(), harness.sdk.configures)
        assertEquals(2, engine.arrivalEvents.size)
        assertEquals(entry, engine.arrivalEvents.last())
    }

    @Test
    fun aCustomSchemeTapIsLabelledAsOne() {
        engine.launchActivity(viewIntent("myapp://open/42"))
        assertEquals("custom_scheme", engine.pending().single()["source"])
    }

    @Test
    fun aWarmTapRecordsOneArrivalThatIsNotTheLaunch() {
        engine.launchActivity(viewIntent(COLD))

        engine.newIntent(WARM)

        val entries = engine.pending()
        assertEquals(listOf(COLD, WARM), urls(entries))
        assertEquals(listOf(true, false), entries.map { it["isLaunch"] })
        assertEquals(emptyList(), harness.sdk.handled)
    }

    @Test
    fun twoTapsOnTheSameUrlAreTwoArrivals() {
        engine.launchActivity(Intent(Intent.ACTION_MAIN))

        engine.newIntent(WARM)
        engine.newIntent(WARM)

        val ids = engine.pending().map { it["arrivalId"] }
        assertEquals(2, ids.toSet().size)
    }

    @Test
    fun oneOsDeliveryReportedByTwoEnginesIsOneArrival() {
        val second = harness.newEngine()
        val activity = createActivity(viewIntent(COLD))
        engine.attachActivity(activity)
        second.attachActivity(activity)
        val warm = viewIntent(WARM)

        engine.activityBinding.newIntent(warm)
        second.activityBinding.newIntent(warm)

        assertEquals(listOf(COLD, WARM), urls(engine.pending()))
    }

    @Test
    fun aRestoredActivityRecordsNoArrival() {
        val saved = engine.run {
            launchActivity(viewIntent(COLD))
            activityBinding.save()
        }
        assertTrue(saved.containsKey(SavedStateMarker.KEY))

        val afterProcessDeath = ProcessHarness().newEngine()
        afterProcessDeath.launchActivity(viewIntent(COLD), pluginState = saved)

        assertEquals(emptyList(), afterProcessDeath.pending())
    }

    @Test
    fun aSavedStateWithoutThePluginMarkerIsAFreshLaunch() {
        engine.launchActivity(viewIntent(COLD), pluginState = Bundle())
        assertEquals(listOf(COLD), urls(engine.pending()))
    }

    @Test
    fun aLaunchFromHistoryRecordsNoArrival() {
        engine.launchActivity(viewIntent(COLD, Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY))
        assertEquals(emptyList(), engine.pending())
    }

    @Test
    fun aWarmIntentFromHistoryRecordsNoArrival() {
        engine.launchActivity(Intent(Intent.ACTION_MAIN))
        engine.activityBinding.newIntent(
            viewIntent(WARM, Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)
        )
        assertEquals(emptyList(), engine.pending())
    }

    @Test
    fun aConfigChangeAndRecreationRecordNoArrivalAndKeepWarmTapsWorking() {
        engine.launchActivity(viewIntent(COLD))
        val saved = engine.activityBinding.save()

        engine.plugin.onDetachedFromActivityForConfigChanges()
        engine.activityBinding.use(createActivity(viewIntent(COLD)))
        engine.plugin.onReattachedToActivityForConfigChanges(engine.activityBinding)
        engine.activityBinding.restore(saved)
        assertEquals(listOf(COLD), urls(engine.pending()))

        engine.newIntent(WARM)
        assertEquals(listOf(COLD, WARM), urls(engine.pending()))
    }

    @Test
    fun theSameActivityReportedAgainRecordsNoSecondLaunch() {
        val activity = createActivity(viewIntent(COLD))
        engine.attachActivity(activity)
        engine.activityBinding.restore(null)
        assertEquals(listOf(COLD), urls(engine.pending()))
    }

    @Test
    fun aLaterFreshActivityRecordsItsLinkAsAnArrivalThatIsNotTheLaunch() {
        engine.launchActivity(viewIntent(COLD))
        engine.plugin.onDetachedFromActivity()

        engine.launchActivity(viewIntent(WARM))

        val entries = engine.pending()
        assertEquals(listOf(COLD, WARM), urls(entries))
        assertFalse(entries.last()["isLaunch"] as Boolean)
    }

    private companion object {
        const val COLD = "https://aplnk.to/cold"
        const val WARM = "https://aplnk.to/warm"
    }
}
