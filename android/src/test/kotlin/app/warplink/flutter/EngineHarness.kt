package app.warplink.flutter

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.test.core.app.ApplicationProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.service.ServicePluginBinding
import io.flutter.plugin.common.BinaryMessenger
import java.lang.reflect.Proxy
import org.robolectric.Robolectric

const val METHOD_CHANNEL = "app.warplink/flutter"
const val ARRIVALS_CHANNEL = "app.warplink/flutter/arrivals"

/** Process state shared by every engine of one test, like the real process singleton. */
class ProcessHarness(
    capacity: Int = ArrivalLedger.DEFAULT_CAPACITY,
    val native: NativeSdk = FakeSdk()
) {
    val app: Application = ApplicationProvider.getApplicationContext()
    val clock = TestClock()
    val logs = mutableListOf<String>()
    val process = PluginProcess.create(native, INLINE_MAIN, clock::read, capacity, logs::add)

    /** The scripted native SDK, for a harness built with the default. */
    val sdk: FakeSdk
        get() = native as FakeSdk

    fun newEngine() = EngineHarness(this)
}

/** One engine: its plugin, a fake messenger, and the Dart side of the channels. */
class EngineHarness(private val harness: ProcessHarness) {
    val plugin = WarpLinkFlutterPlugin(harness.process)
    val messenger = FakeMessenger()
    val activityBinding = FakeActivityBinding()
    private val binding = newBinding(harness.app, messenger)

    init {
        plugin.onAttachedToEngine(binding)
    }

    /** The events Dart received on the arrivals channel. */
    val arrivalEvents: List<Any?>
        get() = messenger.eventsOn(ARRIVALS_CHANNEL)

    fun detachEngine() = plugin.onDetachedFromEngine(binding)

    /** The service half of the embedding: the engine runs inside a service. */
    fun attachService() {
        val serviceBinding =
            Proxy.newProxyInstance(
                ServicePluginBinding::class.java.classLoader,
                arrayOf(ServicePluginBinding::class.java)
            ) { _, _, _ -> null } as ServicePluginBinding
        plugin.onAttachedToService(serviceBinding)
    }

    /** Attaches [activity] and plays the delegate's restore step with [pluginState]. */
    fun attachActivity(activity: Activity, pluginState: Bundle? = null) {
        activityBinding.use(activity)
        plugin.onAttachedToActivity(activityBinding)
        activityBinding.restore(pluginState)
    }

    /** The host creates a fresh Activity for [intent], then the engine attaches to it. */
    fun launchActivity(intent: Intent, pluginState: Bundle? = null): Activity {
        val activity = createActivity(intent)
        attachActivity(activity, pluginState)
        return activity
    }

    fun newIntent(url: String) = activityBinding.newIntent(viewIntent(url))

    fun configure(extra: Map<String, Any?> = emptyMap()): Any? =
        call(
            "configure",
            mapOf(
                "apiKey" to VALID_KEY,
                "apiEndpoint" to "https://api.example.test/v1",
                "debugLogging" to true,
                "linkDomains" to listOf("links.example.test"),
                "automaticDeepLinks" to false,
                "automaticDeferredDeepLinks" to false
            ) + extra
        )

    fun listen() = messenger.listen(ARRIVALS_CHANNEL)

    fun call(method: String, args: Map<String, Any?>? = null): Any? =
        messenger.call(METHOD_CHANNEL, method, args)

    fun callAsync(method: String, args: Map<String, Any?>? = null): Reply =
        messenger.callAsync(METHOD_CHANNEL, method, args)

    /** `getPendingArrivals` as maps. */
    fun pending(): List<Map<*, *>> = (call("getPendingArrivals") as List<*>).map { it as Map<*, *> }

    fun resolve(arrivalId: String): Any? = call("resolveArrival", mapOf("arrivalId" to arrivalId))

    fun claim(arrivalId: String): Any? = call("claimDelivery", mapOf("arrivalId" to arrivalId))
}

/** The Activity exists and its create callbacks ran, but no engine attached yet. */
fun createActivity(intent: Intent): Activity =
    Robolectric.buildActivity(Activity::class.java, intent).create().get()

fun viewIntent(url: String, flags: Int = 0): Intent =
    Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(flags)

private fun newBinding(app: Application, messenger: BinaryMessenger): FlutterPluginBinding =
    FlutterPluginBinding::class.java.constructors.first().newInstance(
        app, null, messenger, null, null, null, null
    ) as FlutterPluginBinding
