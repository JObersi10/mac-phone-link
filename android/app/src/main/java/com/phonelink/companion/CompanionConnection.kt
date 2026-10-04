package com.phonelink.companion

import android.util.Log
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.concurrent.thread

/**
 * The phone's end of the companion link. Connects to the Mac (the server),
 * exchanges newline-delimited base64(AES-GCM) frames whose plaintext is a
 * `{id,type,body}` JSON line, and dispatches incoming packets by type.
 *
 * Transport note: this is a plain TCP client. Over Wi-Fi it dials the Mac's
 * LAN IP directly; the USB fallback uses the same code against 127.0.0.1 after
 * `adb reverse tcp:<port> tcp:<port>` on the host. Bluetooth will later be a
 * second implementation behind the same packet layer.
 */
class CompanionConnection(
    private val host: String,
    private val port: Int,
    private val crypto: CompanionCrypto,
) {
    interface Listener {
        fun onConnecting() {}
        fun onConnected() {}
        /** Disconnected; `reason` is the error message, or null for a clean close. */
        fun onDisconnected(reason: String?) {}
        /** A decoded incoming packet. `body` may be empty. */
        fun onPacket(type: String, body: JSONObject) {}
    }

    @Volatile private var socket: Socket? = null
    @Volatile private var out: OutputStream? = null
    @Volatile private var running = false
    var listener: Listener? = null

    fun start() {
        if (running) return
        running = true
        thread(name = "companion-conn") { runLoop() }
    }

    fun stop() {
        running = false
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        out = null
    }

    val isConnected: Boolean get() = socket?.isConnected == true && running

    private fun runLoop() {
        var reason: String? = null
        try {
            listener?.onConnecting()
            Log.i(TAG, "connecting to $host:$port")
            val s = Socket()
            s.tcpNoDelay = true
            s.connect(InetSocketAddress(host, port), 8000)
            socket = s
            out = s.getOutputStream()
            Log.i(TAG, "connected to $host:$port")
            listener?.onConnected()

            val input = BufferedInputStream(s.getInputStream())
            val buffer = StringBuilder()
            val chunk = ByteArray(1 shl 16)
            while (running) {
                val n = input.read(chunk)
                if (n < 0) break
                // Frames are ASCII base64 + '\n'.
                buffer.append(String(chunk, 0, n, Charsets.US_ASCII))
                var nl = buffer.indexOf("\n")
                while (nl >= 0) {
                    val line = buffer.substring(0, nl)
                    buffer.delete(0, nl + 1)
                    handleFrame(line.trim())
                    nl = buffer.indexOf("\n")
                }
            }
        } catch (e: Exception) {
            reason = "${e.javaClass.simpleName}: ${e.message}"
            Log.w(TAG, "connection ended: $reason")
        } finally {
            running = false
            try { socket?.close() } catch (_: Exception) {}
            socket = null
            out = null
            listener?.onDisconnected(reason)
        }
    }

    private fun handleFrame(base64: String) {
        if (base64.isEmpty()) return
        try {
            val plaintext = crypto.openFromBase64(base64)
            val json = JSONObject(String(plaintext, Charsets.UTF_8))
            val type = json.optString("type")
            val body = json.optJSONObject("body") ?: JSONObject()
            if (type.isNotEmpty()) listener?.onPacket(type, body)
        } catch (e: Exception) {
            Log.w(TAG, "drop undecodable frame: ${e.message}")
        }
    }

    /** Send a `{id,type,body}` packet, encrypted. Safe to call from any thread. */
    fun send(type: String, body: JSONObject) {
        val o = out ?: return
        val packet = JSONObject()
            .put("id", System.currentTimeMillis())
            .put("type", type)
            .put("body", body)
        try {
            val frame = crypto.sealToBase64(packet.toString().toByteArray(Charsets.UTF_8))
            synchronized(this) {
                o.write(frame.toByteArray(Charsets.US_ASCII))
                o.write('\n'.code)
                o.flush()
            }
        } catch (e: Exception) {
            Log.w(TAG, "send failed: ${e.message}")
        }
    }

    companion object { private const val TAG = "CompanionConn" }
}
