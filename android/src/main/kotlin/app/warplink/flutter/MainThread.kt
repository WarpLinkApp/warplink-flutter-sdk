package app.warplink.flutter

import android.os.Handler
import android.os.Looper

/** Runs work on the platform (main) thread. */
fun interface MainThread {
    /** Runs [block] inline when already on the main thread, else posts it. */
    fun run(block: () -> Unit)

    companion object {
        /** `true` when the caller runs on the main looper. */
        fun isCurrent(): Boolean = Looper.myLooper() == Looper.getMainLooper()

        /** The real main looper. */
        val Main: MainThread by lazy {
            val mainLooper = Looper.getMainLooper()
            val handler = Handler(mainLooper)
            MainThread { block ->
                if (Looper.myLooper() == mainLooper) block() else handler.post(block)
            }
        }
    }
}
