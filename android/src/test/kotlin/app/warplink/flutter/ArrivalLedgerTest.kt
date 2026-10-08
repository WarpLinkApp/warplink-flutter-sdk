package app.warplink.flutter

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ArrivalLedgerTest {
    private val clock = TestClock()
    private val logs = mutableListOf<String>()

    private fun ledger(capacity: Int = ArrivalLedger.DEFAULT_CAPACITY) =
        ArrivalLedger(clock::read, { it.startsWith("https://aplnk.to/") }, logs::add, capacity)

    private fun ArrivalLedger.link(name: String) = record("https://aplnk.to/$name", "app_link", false)

    private fun ArrivalLedger.foreign(name: String) = record("https://elsewhere.test/$name", "app_link", false)

    @Test
    fun anEntryCarriesTheContractKeysAndTheClockOfTheMomentItWasRecorded() {
        val ledger = ledger()
        clock.now = 5
        val entry = ledger.record("https://aplnk.to/a", "app_link", true)
        clock.now = 99

        assertEquals(
            setOf("arrivalId", "url", "source", "isLaunch", "seq", "arrivedAtMs"),
            entry.toMap().keys
        )
        assertEquals(5L, entry.toMap()["arrivedAtMs"])
        assertEquals(true, entry.toMap()["isLaunch"])
    }

    @Test
    fun seqStartsAtZeroAndRisesByOnePerEntry() {
        val ledger = ledger()
        val seqs = (1..4).map { ledger.link("l$it").seq }
        assertEquals(listOf(0L, 1L, 2L, 3L), seqs)
    }

    @Test
    fun twoTapsOnTheSameUrlAreTwoEntries() {
        val ledger = ledger()
        val first = ledger.link("same")
        val second = ledger.link("same")
        assertNotEquals(first.arrivalId, second.arrivalId)
        assertEquals(2, ledger.pending().size)
    }

    @Test
    fun pendingListsUndeliveredEntriesOldestFirst() {
        val ledger = ledger()
        val a = ledger.link("a")
        val b = ledger.link("b")
        val c = ledger.link("c")
        ledger.claimDelivery(b.arrivalId)
        assertEquals(listOf(a.arrivalId, c.arrivalId), ledger.pending().map { it.arrivalId })
    }

    @Test
    fun claimDeliveryIsTrueOnceAndFalseForAnUnknownId() {
        val ledger = ledger()
        val entry = ledger.link("a")
        assertTrue(ledger.claimDelivery(entry.arrivalId))
        assertFalse(ledger.claimDelivery(entry.arrivalId))
        assertFalse(ledger.claimDelivery("never-recorded"))
    }

    @Test
    fun aListenerFindsTheEntryAlreadyInTheLedger() {
        val ledger = ledger()
        var seenInLedger = false
        ledger.addListener { seenInLedger = ledger.find(it.arrivalId) === it }
        ledger.link("a")
        assertTrue(seenInLedger)
    }

    @Test
    fun aRemovedListenerHearsNothing() {
        val ledger = ledger()
        val heard = mutableListOf<String>()
        val listener = ArrivalListener { heard.add(it.url) }
        ledger.addListener(listener)
        ledger.removeListener(listener)
        ledger.link("a")
        assertEquals(emptyList<String>(), heard)
    }

    @Test
    fun theLedgerHoldsThirtyTwoEntriesByDefault() {
        val ledger = ledger()
        val ids = (1..40).map { ledger.link("l$it").arrivalId }
        assertEquals(ids.drop(8), ledger.pending().map { it.arrivalId })
        assertEquals(8, logs.size)
    }

    @Test
    fun theBoundDropsTheOldestDeliveredEntryFirstEvenWhenItIsTheLaunchEntry() {
        val ledger = ledger(capacity = 3)
        val launch = ledger.record("https://aplnk.to/launch", "app_link", true)
        val older = ledger.link("a")
        ledger.link("b")
        ledger.claimDelivery(launch.arrivalId)
        ledger.claimDelivery(older.arrivalId)

        ledger.link("c")

        assertNull(ledger.find(launch.arrivalId))
        assertNotNull(ledger.find(older.arrivalId))
        assertTrue(logs.single().contains(launch.arrivalId))
        assertTrue(logs.single().contains("delivered"))
    }

    @Test
    fun withoutADeliveredEntryTheBoundDropsTheOldestForeignUrl() {
        val ledger = ledger(capacity = 3)
        ledger.record("https://aplnk.to/launch", "app_link", true)
        val foreign = ledger.foreign("x")
        val link = ledger.link("a")

        ledger.link("b")

        assertNull(ledger.find(foreign.arrivalId))
        assertNotNull(ledger.find(link.arrivalId))
        assertTrue(logs.single().contains(foreign.arrivalId))
        assertTrue(logs.single().contains("pending"))
    }

    @Test
    fun withOnlyWarpLinkUrlsTheBoundDropsTheOldestUndeliveredNonLaunchEntry() {
        val ledger = ledger(capacity = 3)
        val launch = ledger.record("https://aplnk.to/launch", "app_link", true)
        val oldest = ledger.link("a")
        ledger.link("b")

        ledger.link("c")

        assertNull(ledger.find(oldest.arrivalId))
        assertNotNull(ledger.find(launch.arrivalId))
    }

    @Test
    fun anUndeliveredLaunchEntrySurvivesEveryDrop() {
        val ledger = ledger(capacity = 2)
        val launch = ledger.record("https://aplnk.to/launch", "app_link", true)
        repeat(10) { ledger.link("w$it") }
        assertNotNull(ledger.find(launch.arrivalId))
        assertTrue(ledger.pending().first().isLaunch)
    }

    @Test
    fun seqKeepsRisingAndIsNeverReusedAfterADrop() {
        val ledger = ledger(capacity = 2)
        val seqs = (1..5).map { ledger.link("l$it").seq }
        assertEquals(listOf(0L, 1L, 2L, 3L, 4L), seqs)
    }

    @Test
    fun aDroppedIdAnswersFalseToAClaim() {
        val ledger = ledger(capacity = 2)
        val dropped = ledger.link("a")
        ledger.link("b")
        ledger.link("c")
        assertNull(ledger.find(dropped.arrivalId))
        assertFalse(ledger.claimDelivery(dropped.arrivalId))
    }

    @Test
    fun aBoundDropWaitsForAClaimThatFoundItsEntryAndTheClaimWins() {
        val lookedUp = CountDownLatch(1)
        val release = CountDownLatch(1)
        val ledger =
            ArrivalLedger(clock::read, { true }, logs::add, capacity = 1) {
                lookedUp.countDown()
                release.await()
            }
        val victim = ledger.link("a")
        var claimed = false
        val claiming = thread { claimed = ledger.claimDelivery(victim.arrivalId) }
        lateinit var recording: Thread
        try {
            assertTrue(lookedUp.await(WAIT_SECONDS, TimeUnit.SECONDS), "the claim never reached its lookup")
            recording = thread { ledger.link("b") }
            assertTrue(awaitBlocked(recording), "the drop did not wait for the claim in flight")
        } finally {
            release.countDown()
        }
        claiming.join()
        recording.join()

        assertTrue(claimed)
        assertNull(ledger.find(victim.arrivalId))
        assertTrue(logs.single().contains("delivered"), "the drop named the wrong state: ${logs.single()}")
    }

    private fun awaitBlocked(worker: Thread): Boolean {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(WAIT_SECONDS)
        while (worker.state != Thread.State.BLOCKED && System.nanoTime() < deadline) Thread.sleep(1)
        return worker.state == Thread.State.BLOCKED
    }

    private companion object {
        const val WAIT_SECONDS = 10L
    }
}
