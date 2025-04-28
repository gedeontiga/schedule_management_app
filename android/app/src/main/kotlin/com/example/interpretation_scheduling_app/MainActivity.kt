package com.example.scheduling_management_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import androidx.annotation.NonNull
import android.os.Bundle
import android.view.KeyEvent

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
    
    // Override onActivityResult to properly handle authentication completion
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        // Forward the authentication result to any waiting Flutter plugins
        io.flutter.plugin.common.PluginRegistry.ActivityResultListener::class.java.declaredMethods
            .firstOrNull { it.name == "onActivityResult" }
            ?.let { method ->
                plugins.forEach { plugin ->
                    if (plugin is io.flutter.plugin.common.PluginRegistry.ActivityResultListener) {
                        try {
                            method.invoke(plugin, requestCode, resultCode, data)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error forwarding activity result", e)
                        }
                    }
                }
            }
    }
    
    // Override onKeyDown to properly handle back button during authentication
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            // Let the system handle the back button which should dismiss the authentication screen
            return super.onKeyDown(keyCode, event)
        }
        return super.onKeyDown(keyCode, event)
    }
}
