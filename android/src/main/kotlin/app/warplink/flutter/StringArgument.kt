package app.warplink.flutter

import io.flutter.plugin.common.MethodCall

/**
 * The string under [key], or null when the arguments are not a map, the key is
 * missing, or its value has another type. Unlike `MethodCall.argument`, a value
 * of the wrong type never throws.
 */
internal fun MethodCall.stringArgument(key: String): String? =
    (arguments as? Map<*, *>)?.get(key) as? String
