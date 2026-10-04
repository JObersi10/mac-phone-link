package com.phonelink.companion

import android.util.Base64
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM, matching the Mac side (CryptoKit `AES.GCM`).
 *
 * Wire frame = base64( nonce(12) || ciphertext || tag(16) ). This is exactly
 * what CryptoKit's `SealedBox.combined` produces and what it accepts, so the
 * two ends interoperate with no custom framing. The shared 32-byte key arrives
 * base64-encoded in the pairing QR.
 */
class CompanionCrypto(private val key: ByteArray) {

    init { require(key.size == 32) { "companion key must be 256-bit" } }

    companion object {
        private const val NONCE_LEN = 12
        private const val TAG_BITS = 128

        fun fromBase64Key(b64: String): CompanionCrypto? =
            try {
                val k = Base64.decode(b64.trim(), Base64.DEFAULT)
                if (k.size == 32) CompanionCrypto(k) else null
            } catch (e: Exception) { null }
    }

    /** plaintext -> nonce||ciphertext||tag */
    fun seal(plaintext: ByteArray): ByteArray {
        val nonce = ByteArray(NONCE_LEN).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        val ct = cipher.doFinal(plaintext) // ciphertext + tag
        return nonce + ct
    }

    /** nonce||ciphertext||tag -> plaintext */
    fun open(combined: ByteArray): ByteArray {
        require(combined.size > NONCE_LEN) { "frame too short" }
        val nonce = combined.copyOfRange(0, NONCE_LEN)
        val ct = combined.copyOfRange(NONCE_LEN, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        return cipher.doFinal(ct)
    }

    fun sealToBase64(plaintext: ByteArray): String =
        Base64.encodeToString(seal(plaintext), Base64.NO_WRAP)

    fun openFromBase64(b64: String): ByteArray =
        open(Base64.decode(b64, Base64.NO_WRAP))
}
