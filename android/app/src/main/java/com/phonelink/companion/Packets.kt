package com.phonelink.companion

/**
 * Packet type strings, matching the Mac `CompanionPacketType`. The protocol is
 * reimplemented from its public shape (see NOTICE.md); no KDE Connect source is
 * used. Body field names match the Mac Codable structs exactly.
 */
object Packets {
    const val IDENTITY = "kdeconnect.identity"
    const val BATTERY = "kdeconnect.battery"
    const val FIND_MY_PHONE_REQUEST = "kdeconnect.findmyphone.request"
    const val NOTIFICATION = "kdeconnect.notification"
    const val NOTIFICATION_REQUEST = "kdeconnect.notification.request"
    const val MPRIS = "kdeconnect.mpris"
    const val MPRIS_REQUEST = "kdeconnect.mpris.request"
    const val CLIPBOARD = "kdeconnect.clipboard"
    const val TELEPHONY = "kdeconnect.telephony"
    const val PING = "kdeconnect.ping"
}
