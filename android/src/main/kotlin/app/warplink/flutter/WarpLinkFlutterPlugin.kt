package app.warplink.flutter

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.service.ServiceAware
import io.flutter.embedding.engine.plugins.service.ServicePluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * Flutter plugin for WarpLink: a transport for the process-wide arrival ledger.
 *
 * It records the URLs the host receives, answers the channel methods, and
 * dispatches nothing itself. It needs no edit in the host's MainActivity. The
 * channel contract is `doc/channel-contract.md`.
 */
class WarpLinkFlutterPlugin internal constructor(private val process: PluginProcess) :
    FlutterPlugin,
    ActivityAware,
    ServiceAware,
    PluginRegistry.NewIntentListener {
    constructor() : this(PluginProcess.shared)

    private var session: EngineSession? = null
    private var activity: ActivityPluginBinding? = null

    private val stateListener =
        object : ActivityPluginBinding.OnSaveInstanceStateListener {
            override fun onSaveInstanceState(bundle: Bundle) = SavedStateMarker.write(bundle)

            override fun onRestoreInstanceState(bundle: Bundle?) {
                activity?.activity?.let { process.intake.onSavedStateKnown(it, bundle) }
            }
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        session = EngineSession(binding.applicationContext, binding.binaryMessenger, process)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopObserving()
        session?.close()
        session = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        observe(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        observe(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        stopObserving()
    }

    override fun onDetachedFromActivity() {
        stopObserving()
    }

    override fun onAttachedToService(binding: ServicePluginBinding) {
        session?.answerWithoutActivity()
    }

    override fun onDetachedFromService() = Unit

    override fun onNewIntent(intent: Intent): Boolean {
        process.intake.onNewIntent(intent)
        return false
    }

    private fun observe(binding: ActivityPluginBinding) {
        stopObserving()
        activity = binding
        binding.addOnNewIntentListener(this)
        binding.addOnSaveStateListener(stateListener)
    }

    private fun stopObserving() {
        activity?.removeOnNewIntentListener(this)
        activity?.removeOnSaveStateListener(stateListener)
        activity = null
    }
}
