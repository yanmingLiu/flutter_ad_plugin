package com.example.flutter_ad_plugin_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    private var homeNativeAdFactory: HomeNativeAdFactory? = null
    private var fullScreenNativeAdFactory: FullScreenNativeAdFactory? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        homeNativeAdFactory = HomeNativeAdFactory(this)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "homeListTile",
            homeNativeAdFactory
        )
        fullScreenNativeAdFactory = FullScreenNativeAdFactory(this)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "fullScreenNative",
            fullScreenNativeAdFactory
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "homeListTile")
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "fullScreenNative")
        homeNativeAdFactory = null
        fullScreenNativeAdFactory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
