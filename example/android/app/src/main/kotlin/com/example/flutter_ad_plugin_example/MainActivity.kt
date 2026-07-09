package com.example.flutter_ad_plugin_example

import com.example.flutter_ad_plugin.FullScreenNativeAdFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    private var fullScreenNativeAdFactory: FullScreenNativeAdFactory? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fullScreenNativeAdFactory = FullScreenNativeAdFactory(this)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "fullScreenNative",
            fullScreenNativeAdFactory
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "fullScreenNative")
        fullScreenNativeAdFactory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
