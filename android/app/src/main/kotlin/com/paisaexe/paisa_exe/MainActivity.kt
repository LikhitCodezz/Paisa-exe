package com.paisaexe.app

import android.os.Bundle
import android.content.Intent
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.paisaexe.app/legacy"
    private val csvRequestCode = 8417
    private var csvResult: MethodChannel.Result? = null

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
