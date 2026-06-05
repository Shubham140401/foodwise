package com.foodwise.foodwise

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: AccessibilityBridgeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = AccessibilityBridgeChannel(this, flutterEngine)
        bridge?.startListening()
    }

    override fun onDestroy() {
        bridge?.stopListening()
        super.onDestroy()
    }
}
