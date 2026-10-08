package app.warplink.flutter

import app.warplink.WarpLinkDeepLink
import org.json.JSONArray
import org.json.JSONObject
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Robolectric supplies the real `org.json` classes the native SDK puts in custom params. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DeepLinkMapperTest {
    @Test
    fun customParamsRecurseThroughJsonObjectsAndArrays() {
        val nested =
            JSONObject()
                .put("name", "x")
                .put("count", 2)
                .put("ratio", 0.5)
                .put("on", true)
                .put("gone", JSONObject.NULL)
                .put("tags", JSONArray().put("a").put(1).put(JSONObject.NULL).put(JSONObject().put("k", "v")))
        val link = sampleLink().copy(customParams = mapOf("nested" to nested, "top" to "s"))

        val params = link.toChannelMap()["customParams"] as Map<*, *>

        assertEquals("s", params["top"])
        val mapped = params["nested"] as Map<*, *>
        assertEquals("x", mapped["name"])
        assertEquals(2, mapped["count"])
        assertEquals(0.5, mapped["ratio"])
        assertEquals(true, mapped["on"])
        assertNull(mapped["gone"])
        assertEquals(true, mapped.containsKey("gone"))
        assertEquals(listOf("a", 1, null, mapOf("k" to "v")), mapped["tags"])
    }

    @Test
    fun aJsonNullValueBecomesNull() {
        assertNull(toJsonValue(JSONObject.NULL))
        assertNull(toJsonValue(null))
    }

    @Test
    fun numbersKeepIntegersAndWidenTheRestToDouble() {
        assertEquals(5, toJsonValue(5))
        assertEquals(5_000_000_000L, toJsonValue(5_000_000_000L))
        assertEquals(1.5, toJsonValue(1.5f))
        assertEquals(2.5, toJsonValue(2.5))
    }

    @Test
    fun unknownTypesFallBackToTheirStringForm() {
        assertEquals("abc", toJsonValue(StringBuilder("abc")))
    }

    @Test
    fun emptyCustomParamsAreAnEmptyMap() {
        val link = WarpLinkDeepLink(linkId = "i", destination = "d")
        val map = link.toChannelMap()
        assertEquals(emptyMap<String, Any?>(), map["customParams"])
        assertNull(map["deepLinkUrl"])
        assertNull(map["matchType"])
        assertNull(map["matchConfidence"])
        assertEquals(false, map["matchGuaranteed"])
        assertEquals(false, map["isDeferred"])
    }

    @Test
    fun theDeepLinkMapHasExactlyTheContractKeys() {
        assertEquals(
            setOf(
                "linkId", "destination", "deepLinkUrl", "customParams", "isDeferred",
                "matchType", "matchConfidence", "matchGuaranteed"
            ),
            sampleLink().toChannelMap().keys
        )
    }
}
