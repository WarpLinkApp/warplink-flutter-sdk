package app.warplink.flutter

import android.content.Context
import app.warplink.WarpLinkDeepLink

/**
 * The public native SDK API this plugin uses.
 *
 * Dependency boundary: the plugin and its tests talk to this interface, and
 * [AndroidNativeSdk] is the one class that touches `app.warplink.WarpLink`.
 */
interface NativeSdk {
    val sdkVersion: String
    val isConfigured: Boolean
    val attributionResult: WarpLinkDeepLink?

    fun isAttributionComplete(): Boolean

    /** Configures the native SDK with every automatic path off and no `onLink` sink. */
    fun configure(context: Context, request: ConfigureRequest)

    fun handleDeepLink(url: String, callback: (Result<WarpLinkDeepLink>) -> Unit)

    fun isWarpLinkUrl(url: String): Boolean

    fun checkDeferredDeepLink(callback: (Result<WarpLinkDeepLink?>) -> Unit)
}
