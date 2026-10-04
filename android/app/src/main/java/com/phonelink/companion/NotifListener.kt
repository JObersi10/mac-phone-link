package com.phonelink.companion

import android.app.Notification
import android.content.ComponentName
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * Relays the phone's notifications to the Mac, and (because the same grant
 * unlocks it) wires up media-session access via [MediaRelay].
 */
class NotifListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        MediaRelay.start(applicationContext)
        resendAll()
    }

    override fun onListenerDisconnected() {
        if (instance === this) instance = null
        MediaRelay.stop()
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        send(sbn, cancel = false)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        send(sbn, cancel = true)
    }

    /** Push all current notifications (called right after (re)connect). */
    fun resendAll() {
        val active = try { activeNotifications } catch (e: Exception) { null } ?: return
        for (sbn in active) send(sbn, cancel = false)
    }

    /** Dismiss a notification the Mac asked to clear (id == sbn.key). */
    fun cancel(id: String) {
        try { cancelNotification(id) } catch (_: Exception) {}
    }

    private fun send(sbn: StatusBarNotification, cancel: Boolean) {
        val svc = CompanionService.instance ?: return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        // Skip our own ongoing/foreground notifications and empty ones.
        if (sbn.packageName == packageName) return
        if (title.isNullOrEmpty() && text.isNullOrEmpty() && !cancel) return

        val body = JSONObject()
            .put("id", sbn.key)
            .put("appName", appLabel(sbn.packageName))
            .put("title", title ?: "")
            .put("text", text ?: "")
            .put("isClearable", sbn.isClearable)
            .put("time", sbn.postTime.toString())
        if (cancel) body.put("isCancel", true)
        svc.sendPacket(Packets.NOTIFICATION, body)
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) { pkg }

    companion object {
        @Volatile var instance: NotifListener? = null

        /** Component used to request/verify notification-listener access. */
        fun component(pkg: String) = ComponentName(pkg, NotifListener::class.java.name)
    }
}
