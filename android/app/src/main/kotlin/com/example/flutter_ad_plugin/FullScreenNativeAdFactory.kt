package com.example.flutter_ad_plugin

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.AdChoicesView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

class FullScreenNativeAdFactory(private val context: Context) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_fullscreen, null) as NativeAdView

        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        val adChoicesView = adView.findViewById<AdChoicesView>(R.id.ad_choices_view)
        val iconView = adView.findViewById<ImageView>(R.id.ad_app_icon)
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        val ctaView = adView.findViewById<TextView>(R.id.ad_call_to_action)
        val fullClickArea = adView.findViewById<View>(R.id.ad_full_click_area)
        val iconContainer = adView.findViewById<View>(R.id.ad_icon_container)
        val headlineContainer = adView.findViewById<View>(R.id.ad_headline_container)
        val bodyContainer = adView.findViewById<View>(R.id.ad_body_container)
        val ctaContainer = adView.findViewById<View>(R.id.ad_cta_container)

        adView.mediaView = mediaView
        adView.adChoicesView = adChoicesView
        adView.iconView = iconContainer
        adView.headlineView = fullClickArea
        adView.bodyView = bodyContainer
        adView.advertiserView = advertiserView
        adView.callToActionView = ctaContainer

        mediaView.setImageScaleType(ImageView.ScaleType.CENTER_CROP)
        headlineView.text = nativeAd.headline

        val body = nativeAd.body
        if (body.isNullOrBlank()) {
            bodyContainer.visibility = View.GONE
        } else {
            bodyContainer.visibility = View.VISIBLE
            bodyView.text = body
        }

        val advertiser = nativeAd.advertiser
        if (advertiser.isNullOrBlank()) {
            advertiserView.visibility = View.GONE
        } else {
            advertiserView.visibility = View.GONE
            advertiserView.text = advertiser
        }

        val icon = nativeAd.icon
        if (icon == null) {
            iconContainer.visibility = View.GONE
        } else {
            iconContainer.visibility = View.VISIBLE
            iconView.setImageDrawable(icon.drawable)
        }

        val callToAction = nativeAd.callToAction
        if (callToAction.isNullOrBlank()) {
            ctaContainer.visibility = View.GONE
        } else {
            ctaContainer.visibility = View.VISIBLE
            ctaView.text = callToAction
        }

        adView.post {
            val bottomBound = listOf(
                headlineContainer.top,
                iconContainer.top,
                bodyContainer.top,
                ctaContainer.top,
            ).filter { it > 0 }.minOrNull() ?: adView.height
            val params = fullClickArea.layoutParams as FrameLayout.LayoutParams
            params.width = ViewGroup.LayoutParams.MATCH_PARENT
            params.height = bottomBound.coerceAtLeast(0)
            params.leftMargin = 0
            params.topMargin = 0
            params.rightMargin = 0
            params.bottomMargin = 0
            fullClickArea.layoutParams = params
        }

        mediaView.setMediaContent(nativeAd.mediaContent)
        adView.setNativeAd(nativeAd)
        return adView
    }
}
