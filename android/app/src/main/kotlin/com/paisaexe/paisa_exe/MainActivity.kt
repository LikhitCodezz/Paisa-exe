package com.paisaexe.app

import android.os.Bundle
import android.content.Intent
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.view.View
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.paisaexe.app/legacy"
    private val privacyChannelName = "com.paisaexe.app/privacy"
    private val vaultExecutor = Executors.newSingleThreadExecutor()
    private val csvRequestCode = 8417
    private var csvResult: MethodChannel.Result? = null

    private val privacyPreferences by lazy {
        getSharedPreferences("paisa_private_state", MODE_PRIVATE)
    }
    private val aesAlias = "paisa_hidden_transactions_aes_v1"
    private val hmacAlias = "paisa_hidden_pin_hmac_v1"
    private val hiddenLedgerKey = "hidden_transactions_ciphertext"
    private val pinVerifierKey = "hidden_pin_verifier"
    private val failedAttemptsKey = "hidden_pin_failed_attempts"
    private val lockUntilKey = "hidden_pin_lock_until"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLegacyData" -> {
                        val oldData = getSharedPreferences("paisa_backup", MODE_PRIVATE)
                            .getString("ledger_json", null)
                        result.success(oldData)
                    }
                    "pickCsv" -> {
                        csvResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "text/*"
                        }
                        startActivityForResult(intent, csvRequestCode)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, privacyChannelName)
            .setMethodCallHandler { call, result -> handlePrivacyCall(call, result) }
    }

    private fun handlePrivacyCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                    "hasPrivacyPin" -> performVaultOperation(result) {
                        privacyPreferences.contains(pinVerifierKey)
                    }
                "setPrivacyPin" -> {
                    val pin = call.argument<String>("pin")
                    if (!isValidPin(pin)) {
                        result.error("INVALID_PIN", "PIN must contain exactly four digits.", null)
                    } else {
                            performVaultOperation(result) {
                                check(!privacyPreferences.contains(pinVerifierKey)) {
                                    "A hidden transaction PIN already exists."
                                }
                                privacyPreferences.edit()
                                    .putString(pinVerifierKey, pinMac(pin!!))
                                    .putInt(failedAttemptsKey, 0)
                                    .putLong(lockUntilKey, 0L)
                                    .apply()
                                null
                            }
                    }
                }
                "verifyPrivacyPin" -> {
                    val pin = call.argument<String>("pin")
                        performVaultOperation(result) {
                            if (!isValidPin(pin)) recordFailedPin() else checkPin(pin!!)
                    }
                }
                "changePrivacyPin" -> {
                    val oldPin = call.argument<String>("oldPin")
                    val newPin = call.argument<String>("newPin")
                    if (!isValidPin(oldPin) || !isValidPin(newPin)) {
                        result.error("INVALID_PIN", "PINs must contain exactly four digits.", null)
                    } else {
                            performVaultOperation(result) {
                                check(privacyPreferences.contains(pinVerifierKey)) {
                                    "Create a hidden transaction PIN first."
                                }
                                val verified = checkPin(oldPin!!)
                                if (verified["success"] != true) {
                                    verified
                                } else {
                                    privacyPreferences.edit()
                                        .putString(pinVerifierKey, pinMac(newPin!!))
                                        .putInt(failedAttemptsKey, 0)
                                        .putLong(lockUntilKey, 0L)
                                        .apply()
                                    mapOf(
                                        "success" to true,
                                        "retryAfterSeconds" to 0,
                                        "attemptsRemaining" to 3,
                                    )
                                }
                        }
                    }
                }
                "loadHiddenTransactions" -> performVaultOperation(result) {
                    val packed = privacyPreferences.getString(hiddenLedgerKey, null)
                    if (packed == null) "[]" else decryptHidden(packed)
                }
                "saveHiddenTransactions" -> {
                    val payload = call.arguments as? String
                        ?: return result.error("INVALID_HIDDEN_DATA", "Hidden data is missing.", null)
                    if (payload.length > 5_000_000) {
                        result.error("HIDDEN_DATA_TOO_LARGE", "Hidden transaction data is too large.", null)
                    } else {
                        performVaultOperation(result) {
                            val encrypted = encryptHidden(payload)
                            privacyPreferences.edit()
                                .putString(hiddenLedgerKey, encrypted)
                                .apply()
                            null
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("PRIVACY_SECURITY_ERROR", "Secure privacy operation failed.", null)
        }
    }

    private fun performVaultOperation(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        vaultExecutor.execute {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("PRIVACY_SECURITY_ERROR", "Secure privacy operation failed.", null)
                }
            }
        }
    }

    private fun isValidPin(pin: String?): Boolean = pin != null && Regex("^[0-9]{4}$").matches(pin)

    private fun pinMac(pin: String): String {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        var key = keyStore.getKey(hmacAlias, null) as? SecretKey
        if (key == null) {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
            generator.init(
                KeyGenParameterSpec.Builder(
                    hmacAlias,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                ).setDigests(KeyProperties.DIGEST_SHA256).build(),
            )
            key = generator.generateKey()
        }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(key)
        return Base64.encodeToString(
            mac.doFinal("paisa:hidden-transaction-pin:v1:$pin".toByteArray(Charsets.UTF_8)),
            Base64.NO_WRAP,
        )
    }

    private fun checkPin(pin: String): Map<String, Any> {
        val lockedUntil = privacyPreferences.getLong(lockUntilKey, 0L)
        val now = System.currentTimeMillis()
        if (lockedUntil > now) {
            return mapOf(
                "success" to false,
                "retryAfterSeconds" to ((lockedUntil - now + 999) / 1000).toInt(),
                "attemptsRemaining" to 0,
            )
        }
        val expected = privacyPreferences.getString(pinVerifierKey, null)
            ?: throw IllegalStateException("PIN is not set")
        val actualBytes = Base64.decode(pinMac(pin), Base64.NO_WRAP)
        val expectedBytes = Base64.decode(expected, Base64.NO_WRAP)
        if (MessageDigest.isEqual(expectedBytes, actualBytes)) {
            privacyPreferences.edit()
                .putInt(failedAttemptsKey, 0)
                .putLong(lockUntilKey, 0L)
                .apply()
            return mapOf(
                "success" to true,
                "retryAfterSeconds" to 0,
                "attemptsRemaining" to 3,
            )
        }
        return recordFailedPin()
    }

    private fun recordFailedPin(): Map<String, Any> {
        val attempts = privacyPreferences.getInt(failedAttemptsKey, 0) + 1
        val delaySeconds = if (attempts < 3) 0L else
            (30L * (1L shl (attempts - 3).coerceAtMost(7))).coerceAtMost(3600L)
        val until = if (delaySeconds == 0L) 0L else System.currentTimeMillis() + delaySeconds * 1000L
        privacyPreferences.edit()
            .putInt(failedAttemptsKey, attempts)
            .putLong(lockUntilKey, until)
            .apply()
        return mapOf(
            "success" to false,
            "retryAfterSeconds" to delaySeconds.toInt(),
            "attemptsRemaining" to (3 - attempts).coerceAtLeast(0),
        )
    }

    private fun getOrCreateAesKey(): SecretKey {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            "Android Keystore AES-GCM requires Android 6.0 or newer."
        }
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(aesAlias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                aesAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encryptHidden(plaintext: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateAesKey())
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        val packed = ByteArray(iv.size + ciphertext.size)
        System.arraycopy(iv, 0, packed, 0, iv.size)
        System.arraycopy(ciphertext, 0, packed, iv.size, ciphertext.size)
        return Base64.encodeToString(packed, Base64.NO_WRAP)
    }

    private fun decryptHidden(packedValue: String): String {
        val packed = Base64.decode(packedValue, Base64.NO_WRAP)
        require(packed.size > 12) { "Invalid encrypted hidden transaction data." }
        val iv = packed.copyOfRange(0, 12)
        val ciphertext = packed.copyOfRange(12, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateAesKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    @Deprecated("Deprecated in Android, retained for the Flutter document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != csvRequestCode) return
        val pending = csvResult ?: return
        csvResult = null
        if (resultCode != RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }
        try {
            val content = contentResolver.openInputStream(data.data!!)?.bufferedReader()?.use { it.readText() }
            pending.success(content)
        } catch (error: Exception) {
            pending.error("CSV_READ_FAILED", error.message, null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hideSystemBars()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    @Suppress("DEPRECATION")
    private fun hideSystemBars() {
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
    }
}
