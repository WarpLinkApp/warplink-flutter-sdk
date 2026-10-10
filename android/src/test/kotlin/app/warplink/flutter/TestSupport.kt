package app.warplink.flutter

import android.content.Context
import app.warplink.MatchType
import app.warplink.WarpLinkDeepLink

const val VALID_KEY = "wl_live_abcdefghijklmnopqrstuvwxyz012345"

val INLINE_MAIN = MainThread { it() }

fun sampleLink(id: String = "link-1") =
    WarpLinkDeepLink(
        linkId = id,
        destination = "https://example.com/$id",
        deepLinkUrl = "myapp://$id",
        customParams = mapOf("plan" to "pro", "seats" to 3),
        isDeferred = false,
        matchType = MatchType.DETERMINISTIC,
        matchConfidence = 1.0,
        matchGuaranteed = true
    )

/** A clock the test moves by hand. */
class TestClock(var now: Long = 1_000L) {
    fun read(): Long = now
}

/**
 * A [NativeSdk] that counts every call that reaches the network.
 *
 * `handled` lists the URL of each native `handleDeepLink`, so a test can assert
 * one native request per tap. With [holdResolves] set, an answer waits in
 * [held] until [finishHeld] delivers it.
 */
class FakeSdk : NativeSdk {
    override val sdkVersion = "1.1.1"
    override var isConfigured = false
    override var attributionResult: WarpLinkDeepLink? = null
    var attributionComplete = false
    var warpLinkHosts = setOf("aplnk.to")
    var holdResolves = false
    var handleOutcome: (String) -> Result<WarpLinkDeepLink> = { Result.success(sampleLink(it)) }
    var deferredOutcome: Result<WarpLinkDeepLink?> = Result.success(null)

    val configures = mutableListOf<ConfigureRequest>()
    val handled = mutableListOf<String>()
    val held = mutableListOf<Pair<String, (Result<WarpLinkDeepLink>) -> Unit>>()

    override fun isAttributionComplete() = attributionComplete

    override fun configure(context: Context, request: ConfigureRequest) {
        configures.add(request)
        isConfigured = true
    }

    override fun handleDeepLink(url: String, callback: (Result<WarpLinkDeepLink>) -> Unit) {
        handled.add(url)
        if (holdResolves) held.add(url to callback) else callback(handleOutcome(url))
    }

    override fun isWarpLinkUrl(url: String): Boolean =
        url.substringAfter("://", "").substringBefore("/") in warpLinkHosts

    override fun checkDeferredDeepLink(callback: (Result<WarpLinkDeepLink?>) -> Unit) {
        callback(deferredOutcome)
    }

    /** Delivers the answer of the oldest held native resolve. */
    fun finishHeld() {
        val (url, callback) = held.removeAt(0)
        callback(handleOutcome(url))
    }
}
