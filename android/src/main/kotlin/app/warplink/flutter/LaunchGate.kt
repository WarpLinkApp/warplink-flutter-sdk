package app.warplink.flutter

import java.util.Collections
import java.util.WeakHashMap

/**
 * Holds `getPendingArrivals` until the process knows whether it has a launch
 * arrival (contract section 4.3).
 *
 * [reach] records the process-wide fresh-launch verdict. It holds for the whole
 * process and releases every waiter. An engine that runs inside a service has no
 * Activity to wait for: [releaseEngine] answers that engine alone and never sets
 * the verdict, so a later Activity engine still reaches its own. A missing
 * Activity is never a verdict, because a pre-warmed engine attaches one later.
 */
class LaunchGate {
    private class Waiter(val owner: Any, val callback: () -> Unit)

    private val lock = Any()
    private val waiters = mutableListOf<Waiter>()
    private val answeredEngines = Collections.newSetFromMap(WeakHashMap<Any, Boolean>())
    private var reached = false

    val isReached: Boolean
        get() = synchronized(lock) { reached }

    /** Runs [callback] now when the verdict or an engine answer exists, else when one does. */
    fun await(owner: Any, callback: () -> Unit) {
        val ready =
            synchronized(lock) {
                (reached || owner in answeredEngines).also {
                    if (!it) waiters.add(Waiter(owner, callback))
                }
            }
        if (ready) callback()
    }

    /** The process reached its fresh-launch verdict. */
    fun reach() {
        val released =
            synchronized(lock) {
                reached = true
                waiters.toList().also { waiters.clear() }
            }
        released.forEach { it.callback() }
    }

    /** [owner] needs no Activity verdict: it answers now, and the process verdict stays open. */
    fun releaseEngine(owner: Any) {
        val released =
            synchronized(lock) {
                answeredEngines.add(owner)
                val (mine, others) = waiters.partition { it.owner === owner }
                waiters.clear()
                waiters.addAll(others)
                mine
            }
        released.forEach { it.callback() }
    }

    /** Drops what [owner] waits for, an engine that detached. */
    fun cancel(owner: Any) {
        synchronized(lock) {
            answeredEngines.remove(owner)
            waiters.removeAll { it.owner === owner }
        }
    }
}
