package app.warplink.flutter

import android.content.Context
import android.net.Uri
import app.warplink.WarpLink
import app.warplink.WarpLinkDeepLink
import app.warplink.WarpLinkOptions

/** [NativeSdk] backed by the published Android SDK. */
class AndroidNativeSdk : NativeSdk {
    override val sdkVersion: String
        get() = WarpLink.SDK_VERSION

    override val isConfigured: Boolean
        get() = WarpLink.isConfigured

    override val attributionResult: WarpLinkDeepLink?
        get() = WarpLink.attributionResult

    override fun isAttributionComplete(): Boolean = WarpLink.isAttributionComplete()

    override fun configure(context: Context, request: ConfigureRequest) {
        WarpLink.configure(
            context.applicationContext,
            request.apiKey,
            WarpLinkOptions(
                apiEndpoint = request.apiEndpoint,
                debugLogging = request.debugLogging,
                automaticDeepLinks = false,
                automaticDeferredDeepLinks = false,
                linkDomains = request.linkDomains,
                onLink = null
            )
        )
    }

    override fun handleDeepLink(url: String, callback: (Result<WarpLinkDeepLink>) -> Unit) {
        WarpLink.handleDeepLink(Uri.parse(url), callback)
    }

    override fun isWarpLinkUrl(url: String): Boolean = WarpLink.isWarpLinkUri(Uri.parse(url))

    override fun checkDeferredDeepLink(callback: (Result<WarpLinkDeepLink?>) -> Unit) {
        WarpLink.checkDeferredDeepLink(callback)
    }
}
