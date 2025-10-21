package com.example.scheduling_management_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import android.media.MediaScannerConnection
import android.os.Bundle
import android.view.KeyEvent
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.scheduler.app/media_scanner").setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    val file = File(filePath)
                    MediaScannerConnection.scanFile(
                        applicationContext,
                        arrayOf(file.absolutePath),
                        null
                    ) { _, _ -> }
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "File path was null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Set FLAG_SECURE only once
        // window.setFlags(
        //     android.view.WindowManager.LayoutParams.FLAG_SECURE,
        //     android.view.WindowManager.LayoutParams.FLAG_SECURE
        // )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        // The super call propagates results to plugins like local_auth
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            return super.onKeyDown(keyCode, event)
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onPause() {
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
    }
}