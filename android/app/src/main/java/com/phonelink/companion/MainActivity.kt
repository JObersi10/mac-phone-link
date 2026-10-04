package com.phonelink.companion

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions

/**
 * Entry screen: scan the Mac's QR to pair, grant notification access, and see
 * link status. The real work happens in [CompanionService].
 */
class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView

    private val statusReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { refresh() }
    }

    private val scan = registerForActivityResult(ScanContract()) { result ->
        val contents = result.contents
        if (contents == null) {
            toast("Scan cancelled")
        } else {
            pair(contents)
        }
    }

    private val requestNotifPerm = registerForActivityResult(
        ActivityResultContracts.RequestPermission()) { /* best-effort */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        status = TextView(this).apply { textSize = 15f; setPadding(0, 0, 0, 32) }

        val pairBtn = Button(this).apply {
            text = "Pair with Mac (scan QR)"
            setOnClickListener { startScan() }
        }
        val notifBtn = Button(this).apply {
            text = "Enable notification access"
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
        }
        val disconnectBtn = Button(this).apply {
            text = "Disconnect"
            setOnClickListener { CompanionService.disconnect(this@MainActivity); refresh() }
        }

        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(64, 128, 64, 64)
            addView(TextView(this@MainActivity).apply {
                text = "mac-phone-link companion"; textSize = 22f; setPadding(0, 0, 0, 24)
            })
            addView(status)
            addView(pairBtn)
            addView(notifBtn)
            addView(disconnectBtn)
        })

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED) {
            requestNotifPerm.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        // Opened via a maclink:// link?
        intent?.data?.toString()?.let { if (it.startsWith("maclink://")) pair(it) }

        UpdateChecker.check("JObersi10/mac-phone-link", versionName()) { latest ->
            runOnUiThread {
                if (latest != null) toast("Update available: $latest")
            }
        }
    }

    override fun onResume() {
        super.onResume()
        ContextCompat.registerReceiver(
            this,
            statusReceiver,
            android.content.IntentFilter(CompanionService.ACTION_STATUS),
            ContextCompat.RECEIVER_NOT_EXPORTED)
        refresh()
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(statusReceiver) } catch (_: Exception) {}
    }

    private fun startScan() {
        scan.launch(ScanOptions().apply {
            setDesiredBarcodeFormats(ScanOptions.QR_CODE)
            setPrompt("Scan the QR code shown in the Mac app")
            setBeepEnabled(false)
            setOrientationLocked(false)
        })
    }

    private fun pair(contents: String) {
        val code = PairingCode.parse(contents)
        if (code == null) {
            toast("That QR code isn't a mac-phone-link pairing code")
            return
        }
        Prefs.savePairing(this, code)
        CompanionService.connect(this, code)
        toast("Connecting to ${code.name}…")
        if (!hasNotificationAccess()) {
            toast("Tip: enable notification access to sync notifications")
        }
        refresh()
    }

    private fun refresh() {
        val paired = Prefs.lastPairing(this)
        val notif = if (hasNotificationAccess()) "granted" else "not granted"
        val live = Prefs.status(this)
        status.text = buildString {
            append(if (Prefs.isConnected(this@MainActivity)) "● Connected" else "○ Not connected")
            append("\n")
            append(if (paired != null) "Paired with ${paired.name} (${paired.host}:${paired.port})"
                   else "Not paired yet")
            if (!live.isNullOrEmpty()) { append("\n\n"); append(live) }
            append("\n\nNotification access: ")
            append(notif)
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = NotifListener.component(packageName).flattenToString()
        return enabled.split(":").any { TextUtils.equals(it, me) }
    }

    private fun versionName(): String = try {
        packageManager.getPackageInfo(packageName, 0).versionName ?: "0"
    } catch (e: Exception) { "0" }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
