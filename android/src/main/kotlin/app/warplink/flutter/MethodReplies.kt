package app.warplink.flutter

import app.warplink.WarpLinkDeepLink
import io.flutter.plugin.common.MethodChannel

/**
 * Writes method channel replies on the main thread, and nothing after [close].
 *
 * A detached engine never answers a call that was still open (contract section 7).
 */
class MethodReplies(private val main: MainThread) {
    @Volatile
    private var closed = false

    fun close() {
        closed = true
    }

    fun success(result: MethodChannel.Result, value: Any?) {
        main.run { if (!closed) result.success(value) }
    }

    fun error(result: MethodChannel.Result, error: Throwable) {
        val mapped = error.toChannelError()
        main.run { if (!closed) result.error(mapped.code, mapped.message, mapped.details) }
    }

    fun notImplemented(result: MethodChannel.Result) {
        main.run { if (!closed) result.notImplemented() }
    }

    /** Replies with the deep link map, `null`, or the mapped error of [outcome]. */
    fun link(result: MethodChannel.Result, outcome: Result<WarpLinkDeepLink?>) {
        outcome.fold(
            onSuccess = { success(result, it?.toChannelMap()) },
            onFailure = { error(result, it) }
        )
    }
}
