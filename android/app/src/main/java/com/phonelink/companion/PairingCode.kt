package com.phonelink.companion

import android.net.Uri

/**
 * Parsed contents of the pairing QR shown by the Mac:
 *
 *     maclink://<host>:<port>?name=<percent-encoded>&key=<base64-256bit>
 */
data class PairingCode(
    val host: String,
    val port: Int,
    val name: String,
    val base64Key: String,
) {
    companion object {
        const val SCHEME = "maclink"

        fun parse(s: String): PairingCode? {
            return try {
                val uri = Uri.parse(s.trim())
                if (uri.scheme != SCHEME) return null
                val host = uri.host ?: return null
                val port = uri.port
                val key = uri.getQueryParameter("key") ?: return null
                if (host.isEmpty() || port <= 0 || key.isEmpty()) return null
                PairingCode(host, port, uri.getQueryParameter("name") ?: "Mac", key)
            } catch (e: Exception) { null }
        }
    }
}
