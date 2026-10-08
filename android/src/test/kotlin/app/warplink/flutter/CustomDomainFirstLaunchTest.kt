package app.warplink.flutter

import android.app.Activity
import app.warplink.WarpLink
import app.warplink.WarpLinkOptions
import org.junit.After
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Runs the real native SDK behind the plugin, against a loopback API that
 * never validates the key, so no server answer can have taught it the domain.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CustomDomainFirstLaunchTest {
    private val api = LoopbackApi(RESOLVE_JSON)
    private val harness = ProcessHarness(native = AndroidNativeSdk())
    private val engine = harness.newEngine()

    @After
    fun tearDown() = api.close()

    @Test
    fun `WL-S08 a custom domain link launched before configure resolves through the ledger`() {
        engine.launchActivity(viewIntent(LINK))
        val arrival = engine.pending().single()
        assertEquals(LINK, arrival["url"])
        assertEquals(false, engine.call("isWarpLinkUrl", mapOf("url" to LINK)))

        engine.configure(
            mapOf(
                "apiEndpoint" to api.baseUrl,
                "debugLogging" to false,
                "linkDomains" to listOf(HOST)
            )
        )

        assertEquals(true, engine.call("isWarpLinkUrl", mapOf("url" to LINK)))
        val reply = engine.callAsync("resolveArrival", mapOf("arrivalId" to arrival["arrivalId"]))
        idleMainLooperUntil { reply.answered }
        val link = reply.value as Map<*, *>
        assertEquals("https://example.com", link["destination"])
        assertTrue(api.requestLines.any { it.contains("/links/resolve/abc123?domain=$HOST") })
    }

    @Test
    fun theNativeSdkNeverHandlesALaunchLinkOnItsOwn() {
        engine.configure(automaticHandlingOff())

        launchAfterConfigure()

        assertEquals(emptyList<String>(), resolveRequests())
    }

    @Test
    fun theSameLaunchIsHandledWhenNativeAutomaticHandlingIsOn() {
        WarpLink.configure(
            harness.app,
            VALID_KEY,
            WarpLinkOptions(
                apiEndpoint = api.baseUrl,
                automaticDeepLinks = true,
                automaticDeferredDeepLinks = false,
                linkDomains = listOf(AUTOMATIC_HOST),
                onLink = {}
            )
        )

        launchAfterConfigure()

        assertTrue(resolveRequests().isNotEmpty())
    }

    private fun automaticHandlingOff() =
        mapOf("apiEndpoint" to api.baseUrl, "linkDomains" to listOf(AUTOMATIC_HOST))

    /** Creates the Activity after native registered its lifecycle callbacks, then waits out a resolve. */
    private fun launchAfterConfigure() {
        val activity =
            Robolectric.buildActivity(Activity::class.java, viewIntent("https://$AUTOMATIC_HOST/abc123"))
                .setup()
                .get()
        engine.attachActivity(activity)
        Thread.sleep(AUTOMATIC_HANDLING_WINDOW_MS)
        ShadowLooper.idleMainLooper()
    }

    private fun resolveRequests() = api.requestLines.filter { it.contains("/links/resolve/") }

    private companion object {
        const val AUTOMATIC_HANDLING_WINDOW_MS = 500L
        const val AUTOMATIC_HOST = "automatic.example.test"
        const val HOST = "first-launch.example.test"
        const val LINK = "https://$HOST/abc123"
        const val RESOLVE_JSON =
            """{"id":"550e8400-e29b-41d4-a716-446655440000","slug":"abc123","domain":"first-launch.example.test","destination_url":"https://example.com","ios_url":null,"android_url":"myapp://android/42","custom_params":{},"created_at":"2026-01-01T00:00:00.000Z"}"""
    }
}
