package app.warplink.flutter

import app.warplink.WarpLinkDeepLink
import org.json.JSONArray
import org.json.JSONObject

/** Builds the deep link map of the channel contract (section 3.1). */
fun WarpLinkDeepLink.toChannelMap(): Map<String, Any?> =
    mapOf(
        "linkId" to linkId,
        "destination" to destination,
        "deepLinkUrl" to deepLinkUrl,
        "customParams" to customParams.mapValues { (_, value) -> toJsonValue(value) },
        "isDeferred" to isDeferred,
        "matchType" to matchType?.name?.lowercase(),
        "matchConfidence" to matchConfidence,
        "matchGuaranteed" to matchGuaranteed
    )

/** Builds the attribution map of the channel contract (section 3.2). */
fun WarpLinkDeepLink.toAttributionMap(): Map<String, Any?> =
    mapOf(
        "linkId" to linkId,
        "matchType" to matchType?.name?.lowercase(),
        "matchConfidence" to matchConfidence,
        "matchGuaranteed" to matchGuaranteed,
        "isDeferred" to isDeferred
    )

/**
 * Converts a custom parameter value to a standard codec value.
 *
 * Recursion covers `JSONObject`, `JSONArray`, `Map`, and `Iterable`.
 * `JSONObject.NULL` becomes `null`. Integers keep their integer type and other
 * numbers become doubles. Anything else becomes its string form.
 */
fun toJsonValue(value: Any?): Any? =
    when (value) {
        null, JSONObject.NULL -> null
        is String, is Boolean, is Int, is Long -> value
        is Number -> value.toDouble()
        is JSONObject -> value.keys().asSequence().associateWith { toJsonValue(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { toJsonValue(value.get(it)) }
        is Map<*, *> -> value.entries.associate { (key, item) -> key.toString() to toJsonValue(item) }
        is Iterable<*> -> value.map { toJsonValue(it) }
        else -> value.toString()
    }
