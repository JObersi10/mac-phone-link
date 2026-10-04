package com.phonelink.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import org.json.JSONObject

/**
 * Foreground service that owns the companion link and the feature providers
 * (battery, notifications, media, ring, clipboard). Started once the user pairs.
 */
class CompanionService : Service(), CompanionConnection.Listener {

    private var conn: CompanionConnection? = null
    private var ringtone: android.media.Ringtone? = null

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { sendBattery() }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildOngoingNotification("Not connected"))
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val host = intent.getStringExtra(EXTRA_HOST) ?: return START_STICKY
                val port = intent.getIntExtra(EXTRA_PORT, 0)
                val key = intent.getStringExtra(EXTRA_KEY) ?: return START_STICKY
                connect(host, port, key)
            }
            ACTION_DISCONNECT -> { stopSelf() }
        }
        return START_STICKY
    }

    private fun connect(host: String, port: Int, key: String) {
        val crypto = CompanionCrypto.fromBase64Key(key) ?: run {
            Log.e(TAG, "bad key"); return
        }
        conn?.stop()
        val c = CompanionConnection(host, port, crypto)
        c.listener = this
        conn = c
        c.start()
    }

    // MARK: CompanionConnection.Listener

    override fun onConnected() {
        updateNotification("Connected")
        Prefs.setConnected(this, true)
        // Announce identity + push an initial battery snapshot.
        conn?.send(Packets.IDENTITY, JSONObject()
            .put("deviceName", Build.MODEL)
            .put("deviceType", "phone"))
        sendBattery()
        NotifListener.instance?.resendAll()
        MediaRelay.instance?.resend()
    }

    override fun onDisconnected() {
        updateNotification("Disconnected")
        Prefs.setConnected(this, false)
    }

    override fun onPacket(type: String, body: JSONObject) {
        when (type) {
            Packets.FIND_MY_PHONE_REQUEST -> ring()
            Packets.MPRIS_REQUEST -> MediaRelay.instance?.handleRequest(body)
            Packets.NOTIFICATION_REQUEST -> {
                val cancelId = body.optString("cancel")
                if (cancelId.isNotEmpty()) NotifListener.instance?.cancel(cancelId)
            }
            Packets.CLIPBOARD -> {
                val content = body.optString("content")
                if (content.isNotEmpty()) ClipboardBridge.set(this, content)
            }
            Packets.PING -> conn?.send(Packets.PING, JSONObject())
        }
    }

    // MARK: Feature senders (called by providers)

    fun sendPacket(type: String, body: JSONObject) { conn?.send(type, body) }

    private fun sendBattery() {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val charging = status?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)?.let {
            it == BatteryManager.BATTERY_STATUS_CHARGING || it == BatteryManager.BATTERY_STATUS_FULL
        } ?: false
        conn?.send(Packets.BATTERY, JSONObject()
            .put("currentCharge", level)
            .put("isCharging", charging))
    }

    private fun ring() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.setStreamVolume(AudioManager.STREAM_ALARM,
                am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone?.stop()
            ringtone = RingtoneManager.getRingtone(applicationContext, uri)?.apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
            // Auto-stop after 30s so it isn't stuck ringing.
            android.os.Handler(mainLooper).postDelayed({ ringtone?.stop() }, 30_000)
        } catch (e: Exception) { Log.w(TAG, "ring failed: ${e.message}") }
    }

    override fun onDestroy() {
        conn?.stop()
        ringtone?.stop()
        try { unregisterReceiver(batteryReceiver) } catch (_: Exception) {}
        if (instance === this) instance = null
        Prefs.setConnected(this, false)
        super.onDestroy()
    }

    // MARK: Foreground notification

    private fun buildOngoingNotification(status: String): Notification {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL, "Companion link", NotificationManager.IMPORTANCE_LOW))
        }
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("mac-phone-link")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(status: String) {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(NOTIF_ID, buildOngoingNotification(status))
    }

    companion object {
        private const val TAG = "CompanionService"
        private const val CHANNEL = "companion-link"
        private const val NOTIF_ID = 1

        const val ACTION_CONNECT = "com.phonelink.companion.CONNECT"
        const val ACTION_DISCONNECT = "com.phonelink.companion.DISCONNECT"
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_KEY = "key"

        /** Live instance so providers (NotifListener, MediaRelay) can push packets. */
        @Volatile var instance: CompanionService? = null

        fun connect(context: Context, code: PairingCode) {
            val intent = Intent(context, CompanionService::class.java).apply {
                action = ACTION_CONNECT
                putExtra(EXTRA_HOST, code.host)
                putExtra(EXTRA_PORT, code.port)
                putExtra(EXTRA_KEY, code.base64Key)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun disconnect(context: Context) {
            context.startService(Intent(context, CompanionService::class.java)
                .apply { action = ACTION_DISCONNECT })
        }
    }
}
