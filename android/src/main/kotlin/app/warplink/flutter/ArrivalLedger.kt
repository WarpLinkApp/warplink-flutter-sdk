package app.warplink.flutter

import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.atomic.AtomicLong

/** Told about every entry after the ledger recorded it. */
fun interface ArrivalListener {
    fun onArrival(entry: ArrivalEntry)
}

/**
 * The process-wide arrival ledger (contract section 11).
 *
 * It records every URL the host receives and holds it until Dart claims its
 * delivery. Engines are transports: a detach closes channels and never touches
 * an entry. [record] stores the entry before it notifies a listener. The
 * ledger holds at most [capacity] entries and drops by [LedgerBound].
 *
 * [clock] is a native monotonic clock in milliseconds. [isWarpLinkUrl] feeds
 * the drop order. [onDrop] receives the debug line of a dropped entry.
 * [afterClaimLookup] is a test seam: it runs once a claim found its entry and
 * before that claim takes effect.
 */
class ArrivalLedger(
    private val clock: () -> Long,
    isWarpLinkUrl: (String) -> Boolean,
    private val onDrop: (String) -> Unit,
    private val capacity: Int = DEFAULT_CAPACITY,
    private val afterClaimLookup: () -> Unit = {}
) {
    private val lock = Any()
    private val entries = ArrayList<ArrivalEntry>()
    private val listeners = CopyOnWriteArraySet<ArrivalListener>()
    private val bound = LedgerBound(isWarpLinkUrl)
    private var nextSeq = 0L
    private val configurationEpoch = AtomicLong()
    private val newestResolveSeq = AtomicLong(NO_SEQ)

    /** The native configuration epoch. A resolve that started under an older one is stale. */
    val epoch: Long
        get() = configurationEpoch.get()

    /** Called after native took a changed configuration. */
    fun advanceEpoch() {
        configurationEpoch.incrementAndGet()
    }

    /** Notes that the entry with [seq] started a native resolve. */
    fun markResolveStarted(seq: Long) {
        newestResolveSeq.accumulateAndGet(seq, ::maxOf)
    }

    /** `true` once an arrival after [seq] started a native resolve, which a restart of [seq] would cancel. */
    fun resolveStartedAfter(seq: Long): Boolean = newestResolveSeq.get() > seq

    /** Records one OS delivery, then notifies every listener. */
    fun record(url: String, source: String, isLaunch: Boolean): ArrivalEntry {
        val entry =
            synchronized(lock) {
                if (entries.size >= capacity) dropOneLocked()
                ArrivalEntry(UUID.randomUUID().toString(), url, source, isLaunch, nextSeq++, clock())
                    .also { entries.add(it) }
            }
        listeners.forEach { it.onArrival(entry) }
        return entry
    }

    /** Every entry whose delivery nobody claimed, oldest first. */
    fun pending(): List<ArrivalEntry> =
        synchronized(lock) { entries.filter { !it.isDelivered } }

    fun find(arrivalId: String): ArrivalEntry? =
        synchronized(lock) { entries.firstOrNull { it.arrivalId == arrivalId } }

    /**
     * `true` to the first claim of a held id, `false` to every other call. The
     * lookup and the claim are one step under the ledger lock, so a dropped
     * entry never answers `true`.
     */
    fun claimDelivery(arrivalId: String): Boolean =
        synchronized(lock) {
            val entry = entries.firstOrNull { it.arrivalId == arrivalId }
            if (entry != null) afterClaimLookup()
            entry?.claimDelivery() == true
        }

    /** Stops waiting on behalf of [owner], an engine that detached. */
    fun dropWaiters(owner: Any) {
        val held = synchronized(lock) { entries.toList() }
        held.forEach { it.dropWaiters(owner) }
    }

    fun addListener(listener: ArrivalListener) {
        listeners.add(listener)
    }

    fun removeListener(listener: ArrivalListener) {
        listeners.remove(listener)
    }

    private fun dropOneLocked() {
        val victim = bound.victim(entries) ?: return
        entries.remove(victim)
        onDrop("Dropped arrival ${victim.arrivalId} (${victim.describeState()}) at the ledger bound")
    }

    companion object {
        const val DEFAULT_CAPACITY = 32
        private const val NO_SEQ = -1L
    }
}
