package app.warplink.flutter

import app.warplink.WarpLinkDeepLink
import app.warplink.WarpLinkError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ArrivalResolverTest {
    private val sdk = FakeSdk()
    private val ledger = ArrivalLedger(TestClock()::read, sdk::isWarpLinkUrl, {})
    private val resolver = ArrivalResolver(ledger, sdk)
    private val engineA = Any()
    private val engineB = Any()
    private val replies = mutableListOf<Pair<String, Result<WarpLinkDeepLink?>>>()

    private fun entry() = ledger.record("https://aplnk.to/tap", "app_link", false)

    private fun resolve(id: String, engine: Any, name: String) =
        resolver.resolve(id, engine) { replies.add(name to it) }

    @Test
    fun onlyTheFirstClaimCallsNativeAndLaterCallsJoinTheFlightAndTheAnswer() {
        sdk.holdResolves = true
        val id = entry().arrivalId

        resolve(id, engineA, "first")
        resolve(id, engineB, "joined")
        assertEquals(1, sdk.handled.size)
        assertEquals(emptyList(), replies)

        sdk.finishHeld()
        resolve(id, engineA, "after")

        assertEquals(listOf("first", "joined", "after"), replies.map { it.first })
        assertEquals(1, sdk.handled.size)
        assertEquals(1, replies.map { it.second.getOrNull()?.linkId }.toSet().size)
    }

    @Test
    fun aFailedResolveIsStoredAndEveryCallRepliesTheSameFailure() {
        sdk.handleOutcome = { Result.failure(WarpLinkError.LinkNotFound) }
        val id = entry().arrivalId

        resolve(id, engineA, "first")
        resolve(id, engineB, "second")

        assertEquals(1, sdk.handled.size)
        assertTrue(replies.all { it.second.exceptionOrNull() === WarpLinkError.LinkNotFound })
    }

    @Test
    fun anIdTheLedgerDoesNotHoldRepliesNullWithoutANativeCall() {
        resolve("never-recorded", engineA, "unknown")
        assertNull(replies.single().second.getOrThrow())
        assertEquals(emptyList(), sdk.handled)
    }

    @Test
    fun aDetachedEngineIsNeverAnsweredButTheStoredAnswerServesTheNextOne() {
        sdk.holdResolves = true
        val id = entry().arrivalId
        resolve(id, engineA, "detached")
        resolve(id, engineB, "kept")

        ledger.dropWaiters(engineA)
        sdk.finishHeld()
        resolve(id, engineA, "restarted")

        assertEquals(listOf("kept", "restarted"), replies.map { it.first })
        assertEquals(1, sdk.handled.size)
    }

    @Test
    fun aDeliveredEntryStillRepliesItsStoredAnswer() {
        val id = entry().arrivalId
        resolve(id, engineA, "first")
        ledger.claimDelivery(id)
        resolve(id, engineB, "second")

        assertEquals(1, sdk.handled.size)
        assertEquals("https://aplnk.to/tap", replies.last().second.getOrThrow()?.linkId)
    }

    @Test
    fun aClaimWhileResolvingLetsTheRequestFinishAndKeepsTheAnswer() {
        sdk.holdResolves = true
        val id = entry().arrivalId
        resolve(id, engineA, "first")

        assertTrue(ledger.claimDelivery(id))
        sdk.finishHeld()

        assertEquals(listOf("first"), replies.map { it.first })
        assertEquals(emptyList(), ledger.pending())
    }

    @Test
    fun aNativeExceptionIsStoredAsTheAnswer() {
        sdk.handleOutcome = { throw IllegalStateException("boom") }
        val id = entry().arrivalId

        resolve(id, engineA, "first")
        resolve(id, engineB, "second")

        assertEquals(1, sdk.handled.size)
        assertEquals("boom", replies.last().second.exceptionOrNull()?.message)
    }

    @Test
    fun aResolveThatSettlesUnderAnOlderEpochIsDiscardedAndSentOnceMoreToEveryWaiter() {
        sdk.holdResolves = true
        val id = entry().arrivalId
        resolve(id, engineA, "first")
        resolve(id, engineB, "joined")

        ledger.advanceEpoch()
        sdk.handleOutcome = { Result.success(sampleLink("fresh")) }
        sdk.held.single().second(Result.success(sampleLink("stale")))

        assertEquals(emptyList(), replies)
        assertEquals(2, sdk.handled.size)

        sdk.finishHeld()

        assertEquals(listOf("first", "joined"), replies.map { it.first })
        assertEquals(listOf("fresh", "fresh"), replies.map { it.second.getOrThrow()?.linkId })
        resolve(id, engineA, "after")
        assertEquals(2, sdk.handled.size)
        assertEquals("fresh", replies.last().second.getOrThrow()?.linkId)
    }

    @Test
    fun aStaleResolveWithNobodyWaitingReturnsToPendingAndTheNextCallResolvesAgain() {
        sdk.holdResolves = true
        val id = entry().arrivalId
        resolve(id, engineA, "detached")
        ledger.dropWaiters(engineA)

        ledger.advanceEpoch()
        sdk.finishHeld()
        assertEquals(1, sdk.handled.size)
        assertEquals(emptyList(), replies)

        resolve(id, engineB, "next")
        assertEquals(2, sdk.handled.size)
        sdk.finishHeld()
        assertEquals(listOf("next"), replies.map { it.first })
    }

    @Test
    fun aResolveStartedAfterTheEpochAdvancedIsNotStale() {
        ledger.advanceEpoch()
        val id = entry().arrivalId

        resolve(id, engineA, "first")

        assertEquals(1, sdk.handled.size)
        assertEquals(listOf("first"), replies.map { it.first })
    }

    @Test
    fun aStaleResolveIsNotSentAgainOnceANewerArrivalStartedResolvingAndSettlesSuperseded() {
        sdk.holdResolves = true
        val older = ledger.record("https://aplnk.to/older", "app_link", false)
        val newer = ledger.record("https://aplnk.to/newer", "app_link", false)
        resolve(older.arrivalId, engineA, "older")
        ledger.advanceEpoch()
        resolve(newer.arrivalId, engineB, "newer")

        sdk.held.first { it.first == older.url }.second(Result.success(sampleLink("stale")))

        assertEquals(listOf(older.url, newer.url), sdk.handled)
        assertEquals(listOf("older"), replies.map { it.first })
        assertTrue(replies.single().second.exceptionOrNull() is WarpLinkError.NetworkError)
        resolve(older.arrivalId, engineA, "again")
        assertEquals(2, sdk.handled.size)
        assertTrue(replies.last().second.isFailure)
    }

    @Test
    fun aForeignUrlResolvingMeanwhileDoesNotSupersedeAnOlderStaleResolve() {
        sdk.holdResolves = true
        val older = ledger.record("https://aplnk.to/older", "app_link", false)
        val foreign = ledger.record("https://elsewhere.test/other", "app_link", false)
        resolve(older.arrivalId, engineA, "older")
        ledger.advanceEpoch()
        resolve(foreign.arrivalId, engineB, "foreign")

        sdk.held.first { it.first == older.url }.second(Result.success(sampleLink("stale")))

        assertEquals(listOf(older.url, foreign.url, older.url), sdk.handled)
        assertEquals(emptyList(), replies)

        sdk.handleOutcome = { Result.success(sampleLink("fresh")) }
        sdk.held.last { it.first == older.url }.second(Result.success(sampleLink("fresh")))

        assertEquals(listOf("older"), replies.map { it.first })
        assertEquals("fresh", replies.single().second.getOrThrow()?.linkId)
    }
}
