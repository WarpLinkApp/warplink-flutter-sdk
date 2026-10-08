package app.warplink.flutter

import android.content.Intent

/** What the plugin reads from an Intent the OS delivered. */
object IntentLink {
    /** The URL of [intent], or `null` when it carries none or it came from the recents list. */
    fun urlOf(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        return intent.dataString?.takeIf { it.isNotEmpty() }
    }

    /** A diagnostic label of the OS entry point. Dart never branches on it. */
    fun sourceOf(url: String): String =
        if (url.startsWith("https://", ignoreCase = true) || url.startsWith("http://", ignoreCase = true)) {
            "app_link"
        } else {
            "custom_scheme"
        }
}
