package app.warplink.flutter

import app.warplink.TetherReadResult

/**
 * Builds the Tether read reply of the channel contract (section 3.4).
 *
 * Android never reads the clipboard, so the one answer is a read that found no
 * code and names no reason. Dart reads a null reason as "no reason given".
 */
fun TetherReadResult.toChannelMap(): Map<String, Any?> =
    when (this) {
        TetherReadResult.NoClipboard -> mapOf("kind" to "noCode", "reason" to null)
    }
