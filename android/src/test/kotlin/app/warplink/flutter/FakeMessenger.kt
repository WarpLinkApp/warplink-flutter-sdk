package app.warplink.flutter

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer

/** The answer to one method call. [answered] stays false while native holds the call. */
class Reply {
    var value: Any? = null
    var answered = false
}

/** The in-memory messenger between a plugin and a test that plays Dart. */
class FakeMessenger : BinaryMessenger {
    private val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler?>()
    private val codec = StandardMethodCodec.INSTANCE
    private val events = mutableMapOf<String, MutableList<Any?>>()

    /** Channel names that currently have a handler. */
    val registeredChannels: Set<String>
        get() = handlers.filterValues { it != null }.keys

    fun eventsOn(channel: String): List<Any?> = events[channel].orEmpty()

    /** Calls [method] and returns the success value, or the error code as `error:CODE`. */
    fun call(channel: String, method: String, args: Map<String, Any?>? = null): Any? =
        callAsync(channel, method, args).value

    /** Like [call], but the returned [Reply] fills in whenever native answers. */
    fun callAsync(channel: String, method: String, args: Map<String, Any?>? = null): Reply {
        val reply = Reply()
        val message = codec.encodeMethodCall(MethodCall(method, args)).also { it.rewind() }
        handlers.getValue(channel)!!.onMessage(message) { bytes ->
            reply.value =
                if (bytes == null) {
                    NOT_IMPLEMENTED
                } else {
                    try {
                        codec.decodeEnvelope(bytes.also { it.rewind() })
                    } catch (error: FlutterException) {
                        "error:${error.code}"
                    }
                }
            reply.answered = true
        }
        return reply
    }

    /** Starts a Dart listener on an event channel. */
    fun listen(channel: String) {
        call(channel, "listen")
    }

    /** Ends the Dart listener on an event channel. */
    fun cancel(channel: String) {
        call(channel, "cancel")
    }

    override fun send(channel: String, message: ByteBuffer?) {
        val decoded = codec.decodeEnvelope(message!!.also { it.rewind() })
        events.getOrPut(channel) { mutableListOf() }.add(decoded)
    }

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) =
        send(channel, message)

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?
    ) {
        handlers[channel] = handler
    }

    companion object {
        /** What [call] returns when native answers `notImplemented`. */
        const val NOT_IMPLEMENTED = "notImplemented"
    }
}
