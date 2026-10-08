package app.warplink.flutter

import android.content.Context

/**
 * The process-wide native configuration (contract section 2.1).
 *
 * The native SDK is a singleton, so a second engine, a Dart hot restart, or a
 * second `configure` with identical values reuses the configuration instead of
 * resetting native state. A changed configuration runs the native `configure`.
 * Resolves already in flight finish against the configuration they started
 * with, because the native resolver captures its client when it starts. Native
 * never cancels them on reconfigure. The ledger epoch advances once native took
 * the new configuration, so [ArrivalResolver] discards those answers and sends
 * the resolve again (contract section 11.2).
 */
class NativeConfiguration(private val sdk: NativeSdk, private val ledger: ArrivalLedger) {
    private val lock = Any()
    private var applied: ConfigureRequest? = null

    fun apply(context: Context, request: ConfigureRequest) {
        synchronized(lock) {
            if (applied == request && sdk.isConfigured) return
            sdk.configure(context, request)
            applied = request
            ledger.advanceEpoch()
        }
    }
}
