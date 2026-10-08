package app.warplink.flutter

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Everything one engine registered, so a detach releases it in one step.
 *
 * A detach closes this engine's channels and waits only. The ledger, the stored
 * answers, and the native configuration belong to the process and stay.
 */
class EngineSession(
    context: Context,
    messenger: BinaryMessenger,
    private val process: PluginProcess
) {
    /** Identifies this engine to the launch gate and to waiting resolves. */
    val owner = Any()

    private val replies = MethodReplies(process.main)
    private val arrivals = ArrivalMethods(process, replies, owner)
    private val stream = ArrivalStream(process.ledger, process.main)
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val arrivalsChannel = EventChannel(messenger, ARRIVALS_CHANNEL)

    init {
        methodChannel.setMethodCallHandler(WarpLinkMethodHandler(context, process, replies, arrivals))
        arrivalsChannel.setStreamHandler(stream)
    }

    /** This engine runs inside a service: it answers `getPendingArrivals` without an Activity. */
    fun answerWithoutActivity() {
        process.gate.releaseEngine(owner)
    }

    fun close() {
        methodChannel.setMethodCallHandler(null)
        arrivalsChannel.setStreamHandler(null)
        stream.close()
        replies.close()
        arrivals.close()
    }

    private companion object {
        const val METHOD_CHANNEL = "app.warplink/flutter"
        const val ARRIVALS_CHANNEL = "app.warplink/flutter/arrivals"
    }
}
