package com.phonelink.companion

import android.content.Context

/** Tiny persisted state: last pairing + live connection flag. */
object Prefs {
    private const val FILE = "companion"
    private const val KEY_HOST = "host"
    private const val KEY_PORT = "port"
    private const val KEY_KEY = "key"
    private const val KEY_NAME = "name"
    private const val KEY_CONNECTED = "connected"
    private const val KEY_STATUS = "status"

    private fun prefs(c: Context) = c.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun savePairing(c: Context, code: PairingCode) {
        prefs(c).edit()
            .putString(KEY_HOST, code.host)
            .putInt(KEY_PORT, code.port)
            .putString(KEY_KEY, code.base64Key)
            .putString(KEY_NAME, code.name)
            .apply()
    }

    fun lastPairing(c: Context): PairingCode? {
        val p = prefs(c)
        val host = p.getString(KEY_HOST, null) ?: return null
        val key = p.getString(KEY_KEY, null) ?: return null
        return PairingCode(host, p.getInt(KEY_PORT, 0), p.getString(KEY_NAME, "Mac") ?: "Mac", key)
    }

    fun setConnected(c: Context, connected: Boolean) {
        prefs(c).edit().putBoolean(KEY_CONNECTED, connected).apply()
    }

    fun isConnected(c: Context): Boolean = prefs(c).getBoolean(KEY_CONNECTED, false)

    fun setStatus(c: Context, status: String) {
        prefs(c).edit().putString(KEY_STATUS, status).apply()
    }

    fun status(c: Context): String? = prefs(c).getString(KEY_STATUS, null)
}
