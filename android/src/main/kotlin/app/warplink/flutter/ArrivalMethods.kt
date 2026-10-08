package app.warplink.flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The ledger methods of one engine (contract sections 4.3 to 4.5).
 *
 * [owner] identifies the engine, so a detach drops what it still waits for
 * while the ledger keeps every entry and every stored answer.
 */
class ArrivalMethods(
    private val process: PluginProcess,
    private val replies: MethodReplies,
    private val owner: Any
) {
    /** Answers once the process knows whether it has a launch arrival. */
    fun getPendingArrivals(result: MethodChannel.Result) {
        process.gate.await(owner) {
            replies.success(result, process.ledger.pending().map { it.toMap() })
        }
    }

    fun resolveArrival(call: MethodCall, result: MethodChannel.Result) {
        val arrivalId = call.argument<String>("arrivalId") ?: ""
        process.resolver.resolve(arrivalId, owner) { replies.link(result, it) }
    }

    fun claimDelivery(call: MethodCall, result: MethodChannel.Result) {
        val arrivalId = call.argument<String>("arrivalId") ?: ""
        replies.success(result, process.ledger.claimDelivery(arrivalId))
    }

    /** Drops every wait of this engine. Entries and stored answers stay. */
    fun close() {
        process.gate.cancel(owner)
        process.ledger.dropWaiters(owner)
    }
}
