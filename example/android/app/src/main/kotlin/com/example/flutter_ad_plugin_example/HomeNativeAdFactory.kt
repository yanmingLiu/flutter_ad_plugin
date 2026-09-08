package com.example.flutter_ad_plugin_example

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.RatingBar
import android.widget.TextView
import com.google.android.gms.ads.nativead.AdChoicesView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

class HomeNativeAdFactory(private val context: Context) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_home_card, null) as NativeAdView

        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        val adChoicesView = adView.findViewById<AdChoicesView>(R.id.ad_choices_view)
        val iconView = adView.findViewById<ImageView>(R.id.ad_app_icon)
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        val ctaView = adView.findViewById<Button>(R.id.ad_call_to_action)
        val starRatingView = adView.findViewById<RatingBar>(R.id.ad_stars)

        adView.mediaView = mediaView
        adView.adChoicesView = adChoicesView
        adView.iconView = iconView
        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.advertiserView = advertiserView
        adView.callToActionView = ctaView
        adView.starRatingView = starRatingView

        headlineView.text = nativeAd.headline

        val body = nativeAd.body
        if (body.isNullOrBlank()) {
            bodyView.visibility = View.GONE
        } else {
            bodyView.visibility = View.VISIBLE
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
            iconView.visibility = View.GONE
        } else {
            iconView.visibility = View.VISIBLE
            iconView.setImageDrawable(icon.drawable)
        }

        val callToAction = nativeAd.callToAction
        if (callToAction.isNullOrBlank()) {
            ctaView.visibility = View.GONE
        } else {
            ctaView.visibility = View.VISIBLE
            ctaView.isAllCaps = false
            ctaView.maxLines = 1
            ctaView.text = callToAction
        }

        val starRating = nativeAd.starRating
        if (starRating == null) {
            starRatingView.visibility = View.GONE
        } else {
            starRatingView.visibility = View.GONE
            starRatingView.rating = starRating.toFloat()
        }

        mediaView.setMediaContent(nativeAd.mediaContent)
        adView.setNativeAd(nativeAd)
        return adView
    }
}
