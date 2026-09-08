import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ui/native_ad_view.dart';

/// Widget factory for creating ad display widgets.
///
/// Hides the [google_mobile_ads] dependency from consumers.
/// The host app uses [AdPlugin.widgetFactory] to render ads without
/// directly importing [google_mobile_ads].
///
/// ---
/// Widget 工厂，隐藏 google_mobile_ads 依赖。宿主通过
/// [AdPlugin.widgetFactory] 渲染广告，无需直接导入 google_mobile_ads。
class AdWidgetFactory {
  /// Creates a banner ad widget from a cached banner ad object.
  Widget bannerWidget(Object ad) {
    if (ad is BannerAd) {
      return SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      );
    }
    return const SizedBox.shrink();
  }

  /// Creates a single native ad widget.
  Widget nativeWidget(Object ad, {double height = 280, bool expand = false}) {
    return NativeAdView(ad: ad, height: height, expand: expand);
  }
}
