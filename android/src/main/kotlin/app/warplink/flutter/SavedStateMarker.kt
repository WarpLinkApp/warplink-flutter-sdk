package app.warplink.flutter

import android.os.Bundle

/**
 * The key the plugin writes into Flutter's plugin state bundle.
 *
 * A saved state that carries it came from this plugin's own save, so the
 * Activity is restored. Without it the Activity is fresh (contract section 11.7).
 */
object SavedStateMarker {
    const val KEY = "app.warplink.flutter.activity_saved"

    fun write(pluginState: Bundle) {
        pluginState.putBoolean(KEY, true)
    }

    fun isRestored(pluginState: Bundle?): Boolean = pluginState?.containsKey(KEY) == true
}
