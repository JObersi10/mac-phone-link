package com.phonelink.companion

import android.os.Bundle
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

/// Placeholder entry point. The companion service (Bluetooth / Wi-Fi transport,
/// notification relay, media, battery, mirroring via MediaProjection +
/// AccessibilityService) is the next milestone — see docs/ANDROID_APP.md.
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val version = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (e: Exception) {
            "?"
        }

        val text = TextView(this).apply {
            text = "mac-phone-link companion\nv$version\n\n" +
                "Pairing & transport (Bluetooth / Wi-Fi) coming soon."
            textSize = 18f
            setPadding(64, 128, 64, 64)
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(text)
        })

        // Self-update check against GitHub releases.
        UpdateChecker.check("JObersi10/mac-phone-link", version) { latest ->
            runOnUiThread {
                if (latest != null) {
                    Toast.makeText(this, "Update available: $latest", Toast.LENGTH_LONG).show()
                }
            }
        }
    }
}
