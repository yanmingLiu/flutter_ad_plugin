package com.example.flutter_ad_plugin

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class FlutterAdPlugin : FlutterPlugin {
    private companion object {
        const val TAG = "FlutterAdPlugin"
        const val FULLSCREEN_FACTORY_ID = "fullScreenNative"
        const val HOME_FACTORY_ID = "homeListTile"
        const val MAX_REGISTER_ATTEMPTS = 5
    }

    private var fullScreenFactory: FullScreenNativeAdFactory? = null
    private var homeFactory: HomeNativeAdFactory? = null
    private val registeredFactoryIds = mutableSetOf<String>()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        fullScreenFactory = FullScreenNativeAdFactory(binding.applicationContext)
        homeFactory = HomeNativeAdFactory(binding.applicationContext)
        mainHandler.post {
            registerFactory(binding, FULLSCREEN_FACTORY_ID, fullScreenFactory)
            registerFactory(binding, HOME_FACTORY_ID, homeFactory)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mainHandler.removeCallbacksAndMessages(null)
        for (factoryId in registeredFactoryIds) {
            GoogleMobileAdsPlugin.unregisterNativeAdFactory(
                binding.flutterEngine,
                factoryId
            )
        }
        registeredFactoryIds.clear()
        fullScreenFactory = null
        homeFactory = null
    }

    private fun registerFactory(
        binding: FlutterPlugin.FlutterPluginBinding,
        factoryId: String,
        factory: GoogleMobileAdsPlugin.NativeAdFactory?,
        attempt: Int = 1
    ) {
        val nativeFactory = factory ?: return
        try {
            val registered = GoogleMobileAdsPlugin.registerNativeAdFactory(
                binding.flutterEngine,
                factoryId,
                nativeFactory
            )
            if (registered) registeredFactoryIds.add(factoryId)
        } catch (error: IllegalStateException) {
            if (attempt >= MAX_REGISTER_ATTEMPTS) {
                Log.w(TAG, "Unable to register $factoryId NativeAdFactory", error)
                return
            }
            mainHandler.postDelayed({
                registerFactory(binding, factoryId, factory, attempt + 1)
            }, 100L)
        }
    }
}
