package app.warplink.flutter

import app.warplink.WarpLinkError
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ConfigureTest {
    private val harness = ProcessHarness()
    private val sdk = harness.sdk
    private val engine = harness.newEngine()

    @Test
    fun configureForwardsTheValuesAndRepliesNull() {
        assertNull(engine.configure())
        assertEquals(
            ConfigureRequest(
                apiKey = VALID_KEY,
                apiEndpoint = "https://api.example.test/v1",
                debugLogging = true,
                linkDomains = listOf("links.example.test")
            ),
            sdk.configures.single()
        )
    }

    @Test
    fun configureDefaultsTheEndpointAndDropsNonStringDomains() {
        engine.configure(mapOf("apiEndpoint" to null, "linkDomains" to listOf("a.test", 5, null)))
        val request = sdk.configures.single()
        assertEquals("https://api.warplink.app/v1", request.apiEndpoint)
        assertEquals(listOf("a.test"), request.linkDomains)
    }

    @Test
    fun aMalformedKeyAnswersAnErrorAndLeavesTheEarlierConfigurationAlone() {
        engine.configure()

        val reply = engine.configure(mapOf("apiKey" to "wl_live_short"))

        assertEquals("error:E_INVALID_API_KEY_FORMAT", reply)
        assertEquals(1, sdk.configures.size)
    }

    @Test
    fun aMissingKeyIsAMalformedKey() {
        assertEquals("error:E_INVALID_API_KEY_FORMAT", engine.call("configure"))
        assertEquals(emptyList(), sdk.configures)
    }

    @Test
    fun anIdenticalConfigureAcrossEnginesReusesTheNativeConfiguration() {
        engine.configure()
        engine.configure()
        harness.newEngine().configure()
        assertEquals(1, sdk.configures.size)
    }

    @Test
    fun aChangedConfigurationRunsTheNativeConfigureAgain() {
        engine.configure()
        engine.configure(mapOf("linkDomains" to listOf("other.example.test")))
        assertEquals(2, sdk.configures.size)
    }

    @Test
    fun aChangedConfigureWhileAResolveIsInFlightDiscardsItsAnswerAndDeliversOneFreshOne() {
        engine.configure()
        sdk.holdResolves = true
        engine.launchActivity(viewIntent("https://aplnk.to/cold"))
        val id = engine.pending().single()["arrivalId"] as String
        val reply = engine.callAsync("resolveArrival", mapOf("arrivalId" to id))

        engine.configure(mapOf("linkDomains" to listOf("other.example.test")))
        sdk.handleOutcome = { Result.success(sampleLink("fresh")) }
        sdk.held.single().second(Result.success(sampleLink("stale")))
        assertEquals(2, sdk.handled.size)
        sdk.finishHeld()

        assertEquals("fresh", (reply.value as Map<*, *>)["linkId"])
        assertEquals(2, sdk.handled.size)
    }

    @Test
    fun anIdenticalConfigureWhileAResolveIsInFlightKeepsItAndSendsNoSecondResolve() {
        engine.configure()
        sdk.holdResolves = true
        engine.launchActivity(viewIntent("https://aplnk.to/cold"))
        val id = engine.pending().single()["arrivalId"] as String
        val reply = engine.callAsync("resolveArrival", mapOf("arrivalId" to id))

        engine.configure()
        sdk.finishHeld()

        assertEquals("https://aplnk.to/cold", (reply.value as Map<*, *>)["linkId"])
        assertEquals(1, sdk.handled.size)
    }

    @Test
    fun configureKeepsTheLedger() {
        engine.launchActivity(viewIntent("https://aplnk.to/cold"))
        engine.configure()
        engine.configure(mapOf("apiEndpoint" to "https://other.example.test/v1"))
        assertEquals(1, engine.pending().size)
    }

    @Test
    fun theReadMethodsPassTheNativeAnswersThrough() {
        assertEquals("1.1.1", engine.call("getSdkVersion"))
        assertEquals(false, engine.call("isConfigured"))
        assertEquals(false, engine.call("isAttributionComplete"))
        sdk.attributionComplete = true
        engine.configure()
        assertEquals(true, engine.call("isConfigured"))
        assertEquals(true, engine.call("isAttributionComplete"))
    }

    @Test
    fun attributionBeforeConfigureIsNotConfiguredAndAfterItIsNull() {
        assertEquals("error:E_NOT_CONFIGURED", engine.call("getAttributionResult"))
        engine.configure()
        assertNull(engine.call("getAttributionResult"))
        sdk.attributionResult = sampleLink("attr")
        val map = engine.call("getAttributionResult") as Map<*, *>
        assertEquals(setOf("linkId", "matchType", "matchConfidence", "matchGuaranteed", "isDeferred"), map.keys)
    }

    @Test
    fun isWarpLinkUrlAsksNativeAndAnEmptyUrlIsFalse() {
        assertEquals(true, engine.call("isWarpLinkUrl", mapOf("url" to "https://aplnk.to/a")))
        assertEquals(false, engine.call("isWarpLinkUrl", mapOf("url" to "https://elsewhere.test/a")))
        assertEquals(false, engine.call("isWarpLinkUrl", mapOf("url" to "not a url")))
        assertEquals(false, engine.call("isWarpLinkUrl"))
    }

    @Test
    fun handleDeepLinkIsAnIndependentRequestOutsideTheLedger() {
        engine.launchActivity(viewIntent("https://aplnk.to/cold"))

        engine.call("handleDeepLink", mapOf("url" to "https://aplnk.to/cold"))
        engine.call("handleDeepLink", mapOf("url" to "https://aplnk.to/cold"))

        assertEquals(2, sdk.handled.size)
        assertEquals(1, engine.pending().size)
    }

    @Test
    fun handleDeepLinkRepliesTheMapOrTheMappedError() {
        val map = engine.call("handleDeepLink", mapOf("url" to "https://aplnk.to/a")) as Map<*, *>
        assertEquals("https://aplnk.to/a", map["linkId"])
        sdk.handleOutcome = { Result.failure(WarpLinkError.PasswordRequired) }
        assertEquals("error:E_PASSWORD_REQUIRED", engine.call("handleDeepLink", mapOf("url" to "https://aplnk.to/a")))
        assertEquals("error:E_INVALID_URL", engine.call("handleDeepLink"))
    }

    @Test
    fun theDeferredCheckRepliesTheMapNullOrTheError() {
        assertNull(engine.call("checkDeferredDeepLink"))
        sdk.deferredOutcome = Result.success(sampleLink("deferred"))
        assertEquals("deferred", (engine.call("checkDeferredDeepLink") as Map<*, *>)["linkId"])
        sdk.deferredOutcome = Result.failure(WarpLinkError.NotConfigured)
        assertEquals("error:E_NOT_CONFIGURED", engine.call("checkDeferredDeepLink"))
    }

    @Test
    fun removedAndUnknownMethodsAnswerNotImplemented() {
        listOf("getInitialUrl", "ackArrival", "bogus").forEach {
            assertEquals(FakeMessenger.NOT_IMPLEMENTED, engine.call(it))
        }
    }
}
