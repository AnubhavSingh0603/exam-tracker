package com.examtracker.exam_tracker

import android.content.ClipData
import android.content.ClipboardManager
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Copies a password marked "sensitive": Android 13+ shows no preview of it, and
        // keyboards (Gboard and others) keep it out of their clipboard history.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jobsummit/clipboard").setMethodCallHandler { call, result ->
            if (call.method != "copySensitive") return@setMethodCallHandler result.notImplemented()
            val text = call.argument<String>("text") ?: return@setMethodCallHandler result.error("no_text", null, null)
            val clip = ClipData.newPlainText("JobSummit", text)
            clip.description.extras = PersistableBundle().apply {
                // ClipDescription.EXTRA_IS_SENSITIVE (Android 13); keyboards read the same key earlier too.
                putBoolean("android.content.extra.IS_SENSITIVE", true)
            }
            getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
            result.success(null)
        }
    }
}
