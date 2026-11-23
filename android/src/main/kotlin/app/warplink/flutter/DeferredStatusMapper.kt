package app.warplink.flutter

import app.warplink.DeferredCheckStatus

/**
 * Builds the deferred check status reply of the channel contract (section 3.6):
 * `state`, plus `retryAt` in epoch milliseconds for `waiting` only.
 */
fun DeferredCheckStatus.toChannelMap(): Map<String, Any?> =
    when (this) {
        DeferredCheckStatus.NotChecked -> mapOf("state" to "notChecked")
        DeferredCheckStatus.Checking -> mapOf("state" to "checking")
        DeferredCheckStatus.Matched -> mapOf("state" to "matched")
        DeferredCheckStatus.NoMatch -> mapOf("state" to "noMatch")
        is DeferredCheckStatus.Waiting -> mapOf("state" to "waiting", "retryAt" to retryAtMillis)
        DeferredCheckStatus.SkippedOldInstall -> mapOf("state" to "skippedOldInstall")
        DeferredCheckStatus.Stopped -> mapOf("state" to "stopped")
    }
