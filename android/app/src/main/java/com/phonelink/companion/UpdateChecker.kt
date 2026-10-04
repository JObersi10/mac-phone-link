package com.phonelink.companion

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/// Checks the repo's GitHub Releases for a newer APK. Callback receives the
/// latest version string if it is newer than [current], else null.
object UpdateChecker {
    fun check(repo: String, current: String?, callback: (String?) -> Unit) {
        thread {
            try {
                val url = URL("https://api.github.com/repos/$repo/releases/latest")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    setRequestProperty("Accept", "application/vnd.github+json")
                    connectTimeout = 8000
                    readTimeout = 8000
                }
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                conn.disconnect()
                val tag = JSONObject(body).optString("tag_name").removePrefix("v")
                callback(if (isNewer(tag, current ?: "0.0.0")) tag else null)
            } catch (e: Exception) {
                callback(null)
            }
        }
    }

    private fun isNewer(a: String, b: String): Boolean {
        val pa = a.split(".").map { it.toIntOrNull() ?: 0 }
        val pb = b.split(".").map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(pa.size, pb.size)) {
            val x = pa.getOrElse(i) { 0 }
            val y = pb.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }
}
