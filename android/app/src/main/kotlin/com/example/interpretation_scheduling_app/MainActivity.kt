package com.example.scheduling_management_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import android.os.Bundle
import android.view.KeyEvent

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
    
    // Override onActivityResult to properly handle authentication completion
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        // The super class (FlutterFragmentActivity) should automatically pass results to plugins
        // This override is just to ensure the activity lifecycle is properly managed
    }
    
    // Add this to ensure proper activity state management
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Set proper window flags for authentication activities
        window.setFlags(
            android.view.WindowManager.LayoutParams.FLAG_SECURE,
            android.view.WindowManager.LayoutParams.FLAG_SECURE
        )
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
