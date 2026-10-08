package app.warplink.flutter

import io.flutter.plugin.common.EventChannel

/**
 * The arrivals event channel of one engine (contract section 4.2).
 *
 * The first event after every `onListen` is `{ "type": "ready" }`. Entries are
 * announced after that, once the ledger recorded them. Events are
 * notifications: the ledger is the queue, so nothing is buffered here. After
 * [close] the stream writes nothing.
 */
class ArrivalStream(
    private val ledger: ArrivalLedger,
    private val main: MainThread
) : EventChannel.StreamHandler, ArrivalListener {
    private val lock = Any()
    private var sink: EventChannel.EventSink? = null
    private var closed = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        main.run {
            val open = synchronized(lock) { (!closed && events != null).also { if (it) sink = events } }
            if (open) {
                events?.success(READY)
                ledger.addListener(this)
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) { sink = null }
        ledger.removeListener(this)
    }

    override fun onArrival(entry: ArrivalEntry) {
        main.run {
            val target = synchronized(lock) { sink }
            target?.success(entry.toMap())
        }
    }

    /** Stops every write to this engine's sink. */
    fun close() {
        synchronized(lock) {
            closed = true
            sink = null
        }
        ledger.removeListener(this)
    }

    private companion object {
        val READY = mapOf("type" to "ready")
    }
}
