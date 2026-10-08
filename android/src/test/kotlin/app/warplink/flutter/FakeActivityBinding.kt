package app.warplink.flutter

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/** The Activity half of the Flutter embedding, as the plugin sees it. */
class FakeActivityBinding : ActivityPluginBinding {
    private lateinit var current: Activity
    private val newIntentListeners = mutableSetOf<PluginRegistry.NewIntentListener>()
    private val saveListeners = mutableSetOf<ActivityPluginBinding.OnSaveInstanceStateListener>()

    fun use(activity: Activity) {
        current = activity
    }

    /** The Flutter delegate's restore step: `null` when the Activity starts fresh. */
    fun restore(pluginState: Bundle?) =
        saveListeners.toList().forEach { it.onRestoreInstanceState(pluginState) }

    /** The Flutter delegate's save step: the bundle the plugins wrote their state into. */
    fun save(): Bundle = Bundle().also { bundle -> saveListeners.toList().forEach { it.onSaveInstanceState(bundle) } }

    fun newIntent(intent: Intent) = newIntentListeners.toList().forEach { it.onNewIntent(intent) }

    override fun getActivity() = current

    override fun getLifecycle(): Any = Any()

    override fun addOnNewIntentListener(listener: PluginRegistry.NewIntentListener) {
        newIntentListeners.add(listener)
    }

    override fun removeOnNewIntentListener(listener: PluginRegistry.NewIntentListener) {
        newIntentListeners.remove(listener)
    }

    override fun addOnSaveStateListener(
        listener: ActivityPluginBinding.OnSaveInstanceStateListener
    ) {
        saveListeners.add(listener)
    }

    override fun removeOnSaveStateListener(
        listener: ActivityPluginBinding.OnSaveInstanceStateListener
    ) {
        saveListeners.remove(listener)
    }

    override fun addRequestPermissionsResultListener(
        listener: PluginRegistry.RequestPermissionsResultListener
    ) = Unit

    override fun removeRequestPermissionsResultListener(
        listener: PluginRegistry.RequestPermissionsResultListener
    ) = Unit

    override fun addActivityResultListener(listener: PluginRegistry.ActivityResultListener) = Unit

    override fun removeActivityResultListener(listener: PluginRegistry.ActivityResultListener) =
        Unit

    override fun addOnUserLeaveHintListener(listener: PluginRegistry.UserLeaveHintListener) = Unit

    override fun removeOnUserLeaveHintListener(listener: PluginRegistry.UserLeaveHintListener) =
        Unit

    override fun addOnWindowFocusChangedListener(
        listener: PluginRegistry.WindowFocusChangedListener
    ) = Unit

    override fun removeOnWindowFocusChangedListener(
        listener: PluginRegistry.WindowFocusChangedListener
    ) = Unit
}
