package app.warplink.flutter

import android.os.SystemClock
import android.util.Log

/**
 * Everything the plugin keeps for the whole process (contract section 11.1).
 *
 * Engines are transports: each plugin instance borrows this one object, so a
 * second engine, an engine group, or a Dart hot restart sees the same ledger.
 * [create] builds a fresh set for a test with fake collaborators.
 */
class PluginProcess private constructor(
    val sdk: NativeSdk,
    val main: MainThread,
    val ledger: ArrivalLedger,
    val gate: LaunchGate,
    val intake: IntentIntake,
    val resolver: ArrivalResolver,
    val configuration: NativeConfiguration
) {
    companion object {
        private const val TAG = "WarpLinkFlutter"

        /** The production instance: the real native SDK, the real clock, the real main looper. */
        val shared: PluginProcess by lazy {
            create(AndroidNativeSdk(), MainThread.Main, SystemClock::elapsedRealtime) {
                Log.d(TAG, it)
            }
        }

        fun create(
            sdk: NativeSdk,
            main: MainThread,
            clock: () -> Long,
            capacity: Int = ArrivalLedger.DEFAULT_CAPACITY,
            log: (String) -> Unit = {}
        ): PluginProcess {
            val ledger = ArrivalLedger(clock, sdk::isWarpLinkUrl, log, capacity)
            val gate = LaunchGate()
            return PluginProcess(
                sdk,
                main,
                ledger,
                gate,
                IntentIntake(ledger, gate),
                ArrivalResolver(ledger, sdk, MainThread::isCurrent),
                NativeConfiguration(sdk, ledger)
            )
        }
    }
}
