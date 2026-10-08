package app.warplink.flutter

import app.warplink.WarpLinkDeepLink
import app.warplink.WarpLinkError
import java.util.concurrent.CancellationException

/**
 * Resolves ledger entries through the native manual path, once per entry
 * (contract section 4.4).
 *
 * The first call for an id starts one native `handleDeepLink`. Every later call
 * joins the stored future or the stored answer, so one tap never mints a second
 * tap id. The native callback attaches to the entry, never to a channel reply,
 * so an engine that detaches strands nothing.
 *
 * A resolve that settles under an older configuration epoch than the current
 * one is discarded and sent again, so the stored answer comes from the
 * configuration in force when it settles. When a later arrival started resolving
 * meanwhile, the discarded resolve is not sent again, because the native
 * resolver would cancel the newer request. It settles with a superseded failure.
 * Only a WarpLink URL supersedes: native cancels an older request for those
 * alone, so a foreign URL resolving meanwhile never blocks a restart.
 *
 * [onMainThread] tells whether the caller runs on the platform thread.
 */
class ArrivalResolver(
    private val ledger: ArrivalLedger,
    private val sdk: NativeSdk,
    private val onMainThread: () -> Boolean = { true }
) {
    /** Replies `null` when the ledger does not hold [arrivalId]. */
    fun resolve(
        arrivalId: String,
        owner: Any,
        reply: (Result<WarpLinkDeepLink?>) -> Unit
    ) {
        val entry = ledger.find(arrivalId)
        if (entry == null) {
            reply(Result.success(null))
            return
        }
        when (val join = entry.join(ResolveWaiter(owner, reply), ledger.epoch)) {
            Join.Start -> start(entry)
            Join.Waiting -> Unit
            is Join.Settled -> reply(join.result)
        }
    }

    private fun start(entry: ArrivalEntry) {
        if (sdk.isWarpLinkUrl(entry.url)) ledger.markResolveStarted(entry.seq)
        try {
            sdk.handleDeepLink(entry.url) { settle(entry, it) }
        } catch (error: RuntimeException) {
            settle(entry, Result.failure(error))
        }
    }

    private fun settle(entry: ArrivalEntry, result: Result<WarpLinkDeepLink?>) {
        // The newer-resolve check below is not atomic with the restart. It holds
        // because every native callback and channel call arrives on the main thread.
        assert(onMainThread()) { "ArrivalResolver.settle must run on the main thread" }
        val newerResolveStarted = { ledger.resolveStartedAfter(entry.seq) }
        when (val settlement = entry.settle(result, ledger.epoch, newerResolveStarted, SUPERSEDED)) {
            Settlement.Restart -> start(entry)
            is Settlement.Answered -> settlement.waiters.forEach { it.reply(settlement.result) }
        }
    }

    private companion object {
        val SUPERSEDED: Result<WarpLinkDeepLink?> =
            Result.failure(WarpLinkError.NetworkError(CancellationException("Superseded by a newer tap")))
    }
}
