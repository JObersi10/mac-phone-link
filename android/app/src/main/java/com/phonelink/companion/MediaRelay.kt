package com.phonelink.companion

import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.util.Log
import org.json.JSONObject

/**
 * Bridges the phone's active media session to the Mac's Now Playing: reports
 * the currently-playing track and applies play/pause/next/previous requests.
 * Requires notification-listener access (granted alongside [NotifListener]).
 */
object MediaRelay {
    @Volatile var instance: MediaRelay? = null
    private var appContext: Context? = null
    private var manager: MediaSessionManager? = null
    private var controllers: List<MediaController> = emptyList()
    private val callbacks = mutableMapOf<MediaController, MediaController.Callback>()

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list -> rebind(list ?: emptyList()) }

    fun start(context: Context) {
        appContext = context.applicationContext
        val msm = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager ?: return
        manager = msm
        instance = this
        val component = NotifListener.component(context.packageName)
        try {
            msm.addOnActiveSessionsChangedListener(sessionsListener, component)
            rebind(msm.getActiveSessions(component))
        } catch (e: Exception) {
            Log.w(TAG, "media access denied: ${e.message}")
        }
    }

    fun stop() {
        manager?.removeOnActiveSessionsChangedListener(sessionsListener)
        callbacks.forEach { (c, cb) -> c.unregisterCallback(cb) }
        callbacks.clear()
        controllers = emptyList()
        manager = null
        instance = null
    }

    private fun primary(): MediaController? =
        controllers.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: controllers.firstOrNull()

    private fun rebind(list: List<MediaController>) {
        callbacks.forEach { (c, cb) -> c.unregisterCallback(cb) }
        callbacks.clear()
        controllers = list
        for (c in list) {
            val cb = object : MediaController.Callback() {
                override fun onMetadataChanged(metadata: MediaMetadata?) = resend()
                override fun onPlaybackStateChanged(state: PlaybackState?) = resend()
                override fun onSessionDestroyed() = resend()
            }
            try { c.registerCallback(cb); callbacks[c] = cb } catch (_: Exception) {}
        }
        resend()
    }

    /** Push the current now-playing snapshot. */
    fun resend() {
        val svc = CompanionService.instance ?: return
        val c = primary()
        if (c == null) {
            svc.sendPacket(Packets.MPRIS, JSONObject().put("title", "").put("isPlaying", false))
            return
        }
        val md = c.metadata
        val state = c.playbackState
        val body = JSONObject()
            .put("player", c.packageName)
            .put("title", md?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "")
            .put("artist", md?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "")
            .put("album", md?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "")
            .put("isPlaying", state?.state == PlaybackState.STATE_PLAYING)
            .put("canPause", true).put("canPlay", true)
            .put("canGoNext", true).put("canGoPrevious", true)
            .put("length", md?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L)
            .put("pos", state?.position ?: 0L)
        svc.sendPacket(Packets.MPRIS, body)
    }

    /** Apply an incoming media request from the Mac. */
    fun handleRequest(body: JSONObject) {
        val c = primary() ?: return
        val tc = c.transportControls
        when (body.optString("action")) {
            "Play" -> tc.play()
            "Pause" -> tc.pause()
            "PlayPause" ->
                if (c.playbackState?.state == PlaybackState.STATE_PLAYING) tc.pause() else tc.play()
            "Next" -> tc.skipToNext()
            "Previous" -> tc.skipToPrevious()
            "Stop" -> tc.stop()
        }
    }

    private const val TAG = "MediaRelay"
}
