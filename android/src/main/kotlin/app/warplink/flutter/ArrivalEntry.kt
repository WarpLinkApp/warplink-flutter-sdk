package app.warplink.flutter

import app.warplink.WarpLinkDeepLink

/** A caller waiting for the outcome of one resolve. [owner] is the engine that asked. */
class ResolveWaiter(val owner: Any, val reply: (Result<WarpLinkDeepLink?>) -> Unit)

/** What a [ArrivalEntry.join] caller has to do next. */
sealed interface Join {
    /** First claim: the caller starts the one native resolve. */
    data object Start : Join

    /** The resolve is in flight: the caller's waiter is answered when it settles. */
    data object Waiting : Join

    /** The resolve settled earlier: the caller replies with [result] itself. */
    data class Settled(val result: Result<WarpLinkDeepLink?>) : Join
}

/** What the resolver does once a native resolve settled. */
sealed interface Settlement {
    /** The answer is stored, or was not needed: reply to [waiters] with [result]. */
    data class Answered(val waiters: List<ResolveWaiter>, val result: Result<WarpLinkDeepLink?>) : Settlement

    /** The resolve ran under an older configuration epoch and callers still wait: send it again. */
    data object Restart : Settlement
}

/**
 * One URL the host received (contract section 4.1).
 *
 * The identity fields never change. The resolve state and the delivery flag are
 * guarded by this entry's lock, so the first claim of either one is atomic.
 */
class ArrivalEntry(
    val arrivalId: String,
    val url: String,
    val source: String,
    val isLaunch: Boolean,
    val seq: Long,
    val arrivedAtMs: Long
) {
    private enum class Phase { Pending, Resolving, Settled }

    private var phase = Phase.Pending
    private var outcome: Result<WarpLinkDeepLink?>? = null
    private var resolveEpoch = 0L
    private var delivered = false
    private val waiters = mutableListOf<ResolveWaiter>()

    /** The entry as an arrivals event or a `getPendingArrivals` item. */
    fun toMap(): Map<String, Any?> =
        mapOf(
            "arrivalId" to arrivalId,
            "url" to url,
            "source" to source,
            "isLaunch" to isLaunch,
            "seq" to seq,
            "arrivedAtMs" to arrivedAtMs
        )

    val isDelivered: Boolean
        @Synchronized get() = delivered

    /** `true` to the first caller only. */
    @Synchronized
    fun claimDelivery(): Boolean {
        if (delivered) return false
        delivered = true
        return true
    }

    /**
     * Registers [waiter] and says whether the caller starts the native resolve.
     * A started resolve is stamped with [epoch], the configuration in force.
     */
    @Synchronized
    fun join(waiter: ResolveWaiter, epoch: Long): Join =
        when (phase) {
            Phase.Pending -> {
                phase = Phase.Resolving
                resolveEpoch = epoch
                waiters.add(waiter)
                Join.Start
            }
            Phase.Resolving -> {
                waiters.add(waiter)
                Join.Waiting
            }
            Phase.Settled -> Join.Settled(checkNotNull(outcome))
        }

    /**
     * Stores the answer of a resolve that ran under [currentEpoch] and returns the
     * waiters to reply to. A second answer is ignored. A resolve that started under
     * an older epoch is discarded. With no waiters the entry returns to pending for
     * the next resolve. With waiters it restarts under [currentEpoch], unless
     * [newerResolveStarted] says a later arrival began resolving meanwhile: a
     * restart would cancel that newer request, so the entry settles with
     * [superseded] instead.
     */
    @Synchronized
    fun settle(
        result: Result<WarpLinkDeepLink?>,
        currentEpoch: Long,
        newerResolveStarted: () -> Boolean,
        superseded: Result<WarpLinkDeepLink?>
    ): Settlement {
        if (phase != Phase.Resolving) return Settlement.Answered(emptyList(), result)
        if (resolveEpoch == currentEpoch) return store(result)
        if (waiters.isEmpty()) {
            phase = Phase.Pending
            return Settlement.Answered(emptyList(), result)
        }
        if (newerResolveStarted()) return store(superseded)
        resolveEpoch = currentEpoch
        return Settlement.Restart
    }

    private fun store(result: Result<WarpLinkDeepLink?>): Settlement {
        phase = Phase.Settled
        outcome = result
        return Settlement.Answered(waiters.toList().also { waiters.clear() }, result)
    }

    /** Forgets the waiters of [owner], an engine that detached. */
    @Synchronized
    fun dropWaiters(owner: Any) {
        waiters.removeAll { it.owner === owner }
    }

    /** The state for the drop log line: resolve phase, and whether it was delivered. */
    @Synchronized
    fun describeState(): String =
        "${phase.name.lowercase()}${if (delivered) ", delivered" else ""}"
}
