package app.warplink.flutter

import android.os.Looper
import java.net.InetAddress
import java.net.ServerSocket
import java.net.SocketException
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread
import org.robolectric.Shadows.shadowOf

/**
 * A loopback HTTP stub for the link API: it answers a link resolve with a
 * fixed body and refuses every other request, `/sdk/validate` included.
 *
 * A raw socket, because `com.sun.net.httpserver` is not on the Android unit
 * test classpath.
 */
class LoopbackApi(private val resolveBody: String) {
    private val socket = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))

    /** Every request line the stub read, in arrival order. */
    val requestLines = CopyOnWriteArrayList<String>()

    val baseUrl: String
        get() = "http://127.0.0.1:${socket.localPort}"

    init {
        thread(isDaemon = true, name = "warplink-flutter-loopback") { serve() }
    }

    fun close() = socket.close()

    private fun serve() {
        while (true) {
            val connection =
                try {
                    socket.accept()
                } catch (_: SocketException) {
                    return
                }
            connection.use {
                val reader = it.getInputStream().bufferedReader()
                val requestLine = reader.readLine().orEmpty()
                requestLines.add(requestLine)
                while (reader.readLine().orEmpty().isNotEmpty()) continue
                val resolved = requestLine.contains("/links/resolve/")
                val body = if (resolved) resolveBody else """{"error":{"code":"UNAVAILABLE"}}"""
                val status = if (resolved) "200 OK" else "503 Service Unavailable"
                it.getOutputStream().apply {
                    write(response(status, body).toByteArray())
                    flush()
                }
            }
        }
    }

    private fun response(status: String, body: String) =
        "HTTP/1.1 $status\r\nContent-Type: application/json\r\n" +
            "Content-Length: ${body.toByteArray().size}\r\nConnection: close\r\n\r\n$body"
}

/** Runs due main-looper work, without moving its clock, until [condition] holds. */
fun idleMainLooperUntil(timeoutMs: Long = 10_000, condition: () -> Boolean) {
    val deadline = System.nanoTime() + timeoutMs * 1_000_000
    while (!condition()) {
        check(System.nanoTime() < deadline) { "the awaited work never happened" }
        shadowOf(Looper.getMainLooper()).idle()
        Thread.sleep(5)
    }
}
