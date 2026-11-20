package com.shinezeogame.sbackup

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Mot de passe du NAS, chiffré par une clé du coffre d'Android (AndroidKeyStore) qui ne
 * quitte jamais le téléphone. Il n'est jamais renvoyé à l'interface : seul le code SMB
 * (`SmbChannel`) le lit, au moment de se connecter.
 */
object SecretStore {
    private const val KEY = "sbackup-nas"
    private const val PREFS = "sbackup-secret"
    private const val VALUE = "motDePasse"

    fun save(context: Context, password: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (password.isEmpty()) {
            prefs.edit().remove(VALUE).apply()
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val data = cipher.iv + cipher.doFinal(password.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(VALUE, Base64.encodeToString(data, Base64.NO_WRAP)).apply()
    }

    fun load(context: Context): String {
        val stored = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(VALUE, null) ?: return ""
        return try {
            val data = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data, 0, 12))
            String(cipher.doFinal(data, 12, data.size - 12), Charsets.UTF_8)
        } catch (e: Exception) {
            // Clé perdue (restauration, réinitialisation) : le mot de passe est à ressaisir.
            ""
        }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getEntry(KEY, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}
