package app.warplink.flutter

import android.content.Intent
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Engines are transports: the process-wide ledger outlives every one of them. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class EngineLifecycleTest {
    private val harness = ProcessHarness()
    private val engine = harness.newEngine()

    private fun id(entry: Map<*, *>) = entry["arrivalId"] as String

    @Test
    fun aServiceEngineAnswersAtOnceAndLeavesTheProcessVerdictOpen() {
        val service = harness.newEngine()
        service.attachService()
        val activityEngine = harness.newEngine()

        val serviceReply = service.callAsync("getPendingArrivals")
        val activityReply = activityEngine.callAsync("getPendingArrivals")
        assertTrue(serviceReply.answered)
        assertEquals(emptyList<Any?>(), serviceReply.value)
        assertFalse(activityReply.answered)

        activityEngine.launchActivity(viewIntent(COLD))

        assertTrue(activityReply.answered)
        assertEquals(1, (activityReply.value as List<*>).size)
    }

    @Test
    fun anEngineWithoutAnActivityOrAServiceNeverAnswersEarly() {
        assertFalse(engine.callAsync("getPendingArrivals").answered)
    }

    @Test
    fun anEngineRestartKeepsPendingAndSettledEntries() {
        engine.launchActivity(viewIntent(COLD))
        engine.newIntent(WARM)
        val (cold, warm) = engine.pending()
        val settled = engine.resolve(id(cold))
        engine.detachEngine()

        val restarted = harness.newEngine()

        assertEquals(listOf(id(cold), id(warm)), restarted.pending().map(::id))
        assertEquals(settled, restarted.resolve(id(cold)))
        assertEquals(listOf(COLD), harness.sdk.handled)
        restarted.resolve(id(warm))
        assertEquals(listOf(COLD, WARM), harness.sdk.handled)
    }

    @Test
    fun anEngineThatDetachesMidResolveStrandsNothing() {
        harness.sdk.holdResolves = true
        engine.launchActivity(viewIntent(COLD))
        val arrivalId = id(engine.pending().single())
        val stranded = engine.callAsync("resolveArrival", mapOf("arrivalId" to arrivalId))
        engine.detachEngine()

        harness.sdk.finishHeld()
        val next = harness.newEngine()

        assertFalse(stranded.answered)
        assertEquals(COLD, (next.resolve(arrivalId) as Map<*, *>)["linkId"])
        assertEquals(1, harness.sdk.handled.size)
    }

    @Test
    fun aDeliveryClaimIsTrueOnceAcrossEnginesAndRestarts() {
        engine.launchActivity(viewIntent(COLD))
        val arrivalId = id(engine.pending().single())
        val second = harness.newEngine()

        assertEquals(true, engine.claim(arrivalId))
        assertEquals(false, second.claim(arrivalId))
        assertEquals(false, engine.claim(arrivalId))
        assertEquals(false, harness.newEngine().claim(arrivalId))
        assertEquals(emptyList(), second.pending())
    }

    @Test
    fun aClaimOfAnUnknownIdIsFalseAndAResolveOfItIsNull() {
        assertEquals(false, engine.claim("never-recorded"))
        assertEquals(null, engine.resolve("never-recorded"))
        assertEquals(false, engine.claim(""))
    }

    @Test
    fun aClaimWhileResolvingMarksDeliveredAndTheRequestStillFinishes() {
        harness.sdk.holdResolves = true
        engine.launchActivity(viewIntent(COLD))
        val arrivalId = id(engine.pending().single())
        val reply = engine.callAsync("resolveArrival", mapOf("arrivalId" to arrivalId))

        assertEquals(true, engine.claim(arrivalId))
        harness.sdk.finishHeld()

        assertTrue(reply.answered)
        assertEquals(emptyList(), engine.pending())
        assertEquals(1, harness.sdk.handled.size)
    }

    @Test
    fun readyIsTheFirstEventAfterEveryListen() {
        engine.listen()
        engine.launchActivity(Intent(Intent.ACTION_MAIN))
        engine.newIntent(WARM)
        assertEquals(mapOf("type" to "ready"), engine.arrivalEvents.first())
        assertEquals(2, engine.arrivalEvents.size)

        engine.messenger.cancel(ARRIVALS_CHANNEL)
        engine.listen()
        assertEquals(mapOf("type" to "ready"), engine.arrivalEvents[2])
    }

    @Test
    fun anEntryRecordedBeforeListenIsInTheReplayAndNotInTheEvents() {
        engine.launchActivity(viewIntent(COLD))

        engine.listen()

        assertEquals(listOf<Any?>(mapOf("type" to "ready")), engine.arrivalEvents)
        assertEquals(1, engine.pending().size)
    }

    @Test
    fun theLedgerHoldsAnEntryBeforeItIsAnnounced() {
        var heldAtAnnounce = false
        harness.process.ledger.addListener { heldAtAnnounce = harness.process.ledger.find(it.arrivalId) != null }
        engine.listen()

        engine.launchActivity(viewIntent(COLD))

        assertTrue(heldAtAnnounce)
    }

    @Test
    fun noEventIsWrittenAfterCancelOrDetach() {
        engine.listen()
        engine.messenger.cancel(ARRIVALS_CHANNEL)
        engine.launchActivity(Intent(Intent.ACTION_MAIN))
        engine.newIntent(WARM)
        assertEquals(1, engine.arrivalEvents.size)

        engine.listen()
        engine.detachEngine()
        harness.process.ledger.record(COLD, "app_link", false)
        assertEquals(2, engine.arrivalEvents.size)
    }

    @Test
    fun seqRisesByOneAcrossEnginesAndClaims() {
        engine.listen()
        engine.launchActivity(viewIntent(COLD))
        engine.claim(id(engine.pending().single()))
        val second = harness.newEngine()
        second.activityBinding.use(createActivity(Intent(Intent.ACTION_MAIN)))
        second.plugin.onAttachedToActivity(second.activityBinding)
        second.newIntent(WARM)
        second.newIntent(COLD)

        val seqs = second.pending().map { it["seq"] }
        assertEquals(listOf<Any?>(1L, 2L), seqs)
        val announced = engine.arrivalEvents.drop(1).map { (it as Map<*, *>)["seq"] }
        assertEquals(listOf<Any?>(0L, 1L, 2L), announced)
    }

    @Test
    fun theLedgerBoundKeepsTheUndeliveredLaunchEntry() {
        val bounded = ProcessHarness(capacity = 4).newEngine()
        bounded.launchActivity(viewIntent(COLD))
        repeat(6) { bounded.newIntent("https://aplnk.to/w$it") }

        val entries = bounded.pending()
        assertEquals(4, entries.size)
        assertEquals(COLD, entries.first()["url"])
        assertEquals(listOf(true, false, false, false), entries.map { it["isLaunch"] })
    }

    @Test
    fun onlyTheMethodAndArrivalsChannelsAreRegistered() {
        assertEquals(setOf(METHOD_CHANNEL, ARRIVALS_CHANNEL), engine.messenger.registeredChannels)
    }

    private companion object {
        const val COLD = "https://aplnk.to/cold"
        const val WARM = "https://aplnk.to/warm"
    }
}
