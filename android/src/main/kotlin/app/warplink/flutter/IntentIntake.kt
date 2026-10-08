package app.warplink.flutter

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import java.util.Collections
import java.util.WeakHashMap

/**
 * Turns what the OS delivers into ledger entries, one per OS delivery.
 *
 * Process-wide, like the ledger: every engine's plugin reports to the one
 * instance, and an Activity or an Intent that several engines report is
 * admitted once. The plugin never dispatches a link.
 */
class IntentIntake(
    private val ledger: ArrivalLedger,
    private val gate: LaunchGate
) {
    private val admittedActivities = weakSet<Activity>()
    private val admittedIntents = weakSet<Intent>()

    /**
     * An Activity reported its saved plugin state: [pluginState] is `null` for a
     * fresh launch. The launch Intent becomes an arrival only for a fresh
     * Activity, then the process-wide verdict is reached and waiters released.
     */
    fun onSavedStateKnown(activity: Activity, pluginState: Bundle?) {
        if (!admittedActivities.add(activity)) return
        val intent = activity.intent
        val url = if (SavedStateMarker.isRestored(pluginState)) null else IntentLink.urlOf(intent)
        if (url != null && intent != null && admittedIntents.add(intent)) {
            ledger.record(url, IntentLink.sourceOf(url), isLaunch = !gate.isReached)
        }
        gate.reach()
    }

    /** A running Activity received [intent]. */
    fun onNewIntent(intent: Intent) {
        if (!admittedIntents.add(intent)) return
        val url = IntentLink.urlOf(intent) ?: return
        ledger.record(url, IntentLink.sourceOf(url), isLaunch = false)
    }

    private fun <T> weakSet(): MutableSet<T> =
        Collections.synchronizedSet(Collections.newSetFromMap(WeakHashMap<T, Boolean>()))
}
