package app.warplink.flutter

import android.content.Context
import app.warplink.WarpLinkError
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dispatches the method channel calls of one engine (contract section 2).
 *
 * Replies always happen on the main thread. This class never dispatches a
 * link: arrivals reach Dart through the ledger methods only.
 */
class WarpLinkMethodHandler(
    private val context: Context,
    private val process: PluginProcess,
    private val replies: MethodReplies,
    private val arrivals: ArrivalMethods
) : MethodChannel.MethodCallHandler {
    private val sdk = process.sdk

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            dispatch(call, result)
        } catch (error: Exception) {
            replies.error(result, error)
        }
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> configure(call, result)
            "handleDeepLink" -> handleDeepLink(call, result)
            "isWarpLinkUrl" -> replies.success(result, sdk.isWarpLinkUrl(urlArgument(call) ?: ""))
            "checkDeferredDeepLink" ->
                sdk.checkDeferredDeepLink { replies.link(result, it) }
            "getAttributionResult" -> attributionResult(result)
            "isConfigured" -> replies.success(result, sdk.isConfigured)
            "isAttributionComplete" -> replies.success(result, sdk.isAttributionComplete())
            "getSdkVersion" -> replies.success(result, sdk.sdkVersion)
            "getPendingArrivals" -> arrivals.getPendingArrivals(result)
            "resolveArrival" -> arrivals.resolveArrival(call, result)
            "claimDelivery" -> arrivals.claimDelivery(call, result)
            else -> replies.notImplemented(result)
        }
    }

    private fun configure(call: MethodCall, result: MethodChannel.Result) {
        val request =
            ConfigureArguments.parse(call.arguments as? Map<*, *>).getOrElse {
                replies.error(result, it)
                return
            }
        process.configuration.apply(context, request)
        replies.success(result, null)
    }

    private fun handleDeepLink(call: MethodCall, result: MethodChannel.Result) {
        val url = urlArgument(call)
        if (url == null) {
            replies.error(result, WarpLinkError.InvalidUrl)
            return
        }
        sdk.handleDeepLink(url) { replies.link(result, it) }
    }

    private fun attributionResult(result: MethodChannel.Result) {
        if (!sdk.isConfigured) {
            replies.error(result, WarpLinkError.NotConfigured)
            return
        }
        replies.success(result, sdk.attributionResult?.toAttributionMap())
    }

    private fun urlArgument(call: MethodCall): String? = call.argument<String>("url")
}
