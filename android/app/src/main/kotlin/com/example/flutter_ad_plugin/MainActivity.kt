package com.example.flutter_ad_plugin

import android.os.Bundle
import com.facebook.FacebookSdk
import com.facebook.LoggingBehavior
import com.facebook.appevents.AppEventsConstants
import com.facebook.appevents.AppEventsLogger
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    private val facebookChannel = "facebook_sdk_init"
    private var homeNativeAdFactory: HomeNativeAdFactory? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        homeNativeAdFactory = HomeNativeAdFactory(this)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "homeListTile",
            homeNativeAdFactory
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            facebookChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeFbSDK" -> {
                    try {
                        val appId = call.argument<String>("appId")
                        val token = call.argument<String>("token")
                        if (appId.isNullOrBlank() || token.isNullOrBlank()) {
                            result.error(
                                "INVALID_ARGUMENTS",
                                "Facebook appId and token are required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        FacebookSdk.setAutoInitEnabled(false)
                        FacebookSdk.setApplicationId(appId)
                        FacebookSdk.setClientToken(token)
                        FacebookSdk.sdkInitialize(this)
                        FacebookSdk.fullyInitialize()
                        AppEventsLogger.activateApp(application)
                        FacebookSdk.setIsDebugEnabled(true)
                        FacebookSdk.addLoggingBehavior(LoggingBehavior.APP_EVENTS)
                        FacebookSdk.addLoggingBehavior(LoggingBehavior.REQUESTS)
                        FacebookSdk.addLoggingBehavior(LoggingBehavior.DEVELOPER_ERRORS)

                        result.success("Facebook SDK initialized")
                    } catch (e: Exception) {
                        result.error(
                            "INITIALIZATION_ERROR",
                            "Failed to initialize Facebook SDK: ${e.message}",
                            null
                        )
                    }
                }

                "logAdImpression" -> {
                    try {
                        val value = call.argument<Double>("value")
                        val currency = call.argument<String>("currency")
                        if (value == null || currency.isNullOrBlank()) {
                            result.error(
                                "INVALID_ARGUMENTS",
                                "Ad impression value and currency are required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val params = Bundle()
                        params.putString(AppEventsConstants.EVENT_PARAM_CURRENCY, currency)
                        AppEventsLogger.newLogger(this).logEvent(
                            AppEventsConstants.EVENT_NAME_AD_IMPRESSION,
                            value,
                            params
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error(
                            "LOG_AD_IMPRESSION_ERROR",
                            "Failed to log Facebook ad impression: ${e.message}",
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "homeListTile")
        homeNativeAdFactory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
