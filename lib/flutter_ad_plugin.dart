import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad/analytics/ad_event_reporter.dart';
import 'ad/config/ad_config_repository.dart';
import 'ad/core/ad_enums.dart';
import 'ad/service/ad_service.dart';
import 'ad/ui/native_ad_view.dart';

export 'ad/core/ad_config.dart';
export 'ad/core/ad_enums.dart';
export 'ad/ui/native_ad_view.dart';

class FlutterAdPlugin {
  FlutterAdPlugin._();

  static Future<void> init({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
  }) {
    return AdService.instance.initWith(
      configRepository: configRepository,
      eventReporter: eventReporter,
    );
  }

  static Future<bool> preload(PlacementType placement) {
    return AdService.instance.preload(placement);
  }
  static Future<bool> preloadByKey(String placementKey) {
    return AdService.instance.preload(placementKey);
  }

  static Future<bool> show(PlacementType placement, {String? placementLabel}) {
    return AdService.instance.show(placement, placementLabel: placementLabel);
  }
  static Future<bool> showByKey(String placementKey, {String? placementLabel}) {
    return AdService.instance.show(
      placementKey,
      placementLabel: placementLabel,
    );
  }

  static Future<bool> loadNative(PlacementType placement) {
    return AdService.instance.loadNative(placement);
  }
  static Future<bool> loadNativeByKey(String placementKey) {
    return AdService.instance.loadNative(placementKey);
  }

  static NativeAd? getNativeAd(PlacementType placement) {
    return AdService.instance.getNativeAd(placement);
  }
  static NativeAd? getNativeAdByKey(String placementKey) {
    return AdService.instance.getNativeAd(placementKey);
  }

  static Future<NativeAd?> showNative(
    PlacementType placement, {
    String? placementLabel,
  }) {
    return AdService.instance.showNative(
      placement,
      placementLabel: placementLabel,
    );
  }

  static Widget nativeAdWidget({
    required NativeAd ad,
    double height = 280,
  }) {
    return NativeAdView(ad: ad, height: height);
  }
}
