package com.phonelink.companion

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context

/** Writes text the Mac copied into the phone's clipboard. */
object ClipboardBridge {
    fun set(context: Context, text: String) {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        cm.setPrimaryClip(ClipData.newPlainText("mac-phone-link", text))
    }
}
