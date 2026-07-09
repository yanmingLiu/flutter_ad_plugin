package com.example.flutter_ad_plugin

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class FlutterAdPlugin : FlutterPlugin {
    private companion object {
        const val TAG = "FlutterAdPlugin"
        const val FACTORY_ID = "fullScreenNative"
        const val MAX_REGISTER_ATTEMPTS = 5
    }

    private var factory: FullScreenNativeAdFactory? = null
    private var isRegistered = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        factory = FullScreenNativeAdFactory(binding.applicationContext)
        mainHandler.post {
            registerFactory(binding)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mainHandler.removeCallbacksAndMessages(null)
        if (isRegistered) {
            GoogleMobileAdsPlugin.unregisterNativeAdFactory(
                binding.flutterEngine,
                FACTORY_ID
            )
        }
        isRegistered = false
        factory = null
    }

    private fun registerFactory(
        binding: FlutterPlugin.FlutterPluginBinding,
        attempt: Int = 1
    ) {
        val nativeFactory = factory ?: return
        try {
            isRegistered = GoogleMobileAdsPlugin.registerNativeAdFactory(
                binding.flutterEngine,
                FACTORY_ID,
                nativeFactory
            )
        } catch (error: IllegalStateException) {
            if (attempt >= MAX_REGISTER_ATTEMPTS) {
                Log.w(TAG, "Unable to register $FACTORY_ID NativeAdFactory", error)
                return
            }
            mainHandler.postDelayed({
                registerFactory(binding, attempt + 1)
            }, 100L)
        }
    }
}
