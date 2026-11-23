package app.warplink.flutter

import android.content.Context
import app.warplink.DeferredCheckStatus
import app.warplink.ReferralClaimResult
import app.warplink.TetherReadResult
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

    /** The receipt of the last Tether test code, or `null` when none was read. */
    val lastTetherTestReceipt: String?

    /** Where the deferred check stands. Sends no request. */
    val deferredCheckStatus: DeferredCheckStatus

    fun isAttributionComplete(): Boolean

    /** Configures the native SDK with every automatic path off and no `onLink` sink. */
    fun configure(context: Context, request: ConfigureRequest)

    fun handleDeepLink(url: String, callback: (Result<WarpLinkDeepLink>) -> Unit)

    fun isWarpLinkUrl(url: String): Boolean

    fun checkDeferredDeepLink(callback: (Result<WarpLinkDeepLink?>) -> Unit)

    /** Hands pasted invitation text to the native SDK, which decides what it is. */
    fun redeemInvitation(text: String, callback: (Result<WarpLinkDeepLink?>) -> Unit)

    /**
     * Clears this install's attribution state. A live key is a no-op success. The
     * failure is `DecodingError` when a stored item could not be deleted.
     */
    fun clearAttribution(): Result<Unit>

    /** Claims the referral behind this install for [installerId]. */
    fun claimReferral(installerId: String, callback: (Result<ReferralClaimResult>) -> Unit)

    /** Reads a Tether code. Android never reads the clipboard, so the answer is `NoClipboard`. */
    fun readTether(callback: (Result<TetherReadResult>) -> Unit)
}
