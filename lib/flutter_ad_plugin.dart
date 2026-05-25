import 'package:flutter/widgets.dart';

import 'src/core/ad_config.dart';
import 'src/core/ad_enums.dart';
import 'src/engine/ad_engine.dart';
import 'src/ui/native_ad_view.dart';
import 'src/utils/ad_reporter.dart';

export 'src/core/ad_config.dart';
export 'src/core/ad_enums.dart';
export 'src/ui/native_ad_view.dart';
export 'src/utils/ad_reporter.dart';

class FlutterAdPlugin {
  FlutterAdPlugin._();

  static Future<void> init({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
  }) {
    return AdEngine.instance.initWith(
      configRepository: configRepository,
      eventReporter: eventReporter,
    );
  }

  static Future<bool> preload(PlacementType placement, {String? eventName}) {
    return AdEngine.instance.preload(placement, eventName: eventName);
  }

  static Future<bool> show(PlacementType placement, {String? placementLabel, String? eventName}) {
    return AdEngine.instance.show(placement, placementLabel: placementLabel, eventName: eventName);
  }

  static Future<bool> loadNative(PlacementType placement, {String? eventName}) {
    return AdEngine.instance.preloadNative(placement, eventName: eventName);
  }

  static Object? getNativeAd(PlacementType placement) {
    return AdEngine.instance.getNativeAd(placement);
  }

  static List<Object> getNativeAds(PlacementType placement, {int count = 2}) {
    return AdEngine.instance.getNativeAds(placement, count: count);
  }

  static Widget nativeAdWidget({required Object ad, double height = 280}) {
    return NativeAdView(ad: ad, height: height);
  }

  static Widget dualNativeAdWidget({
    required List<Object> ads,
    double height = 600,
    Axis direction = Axis.vertical,
  }) {
    return DualNativeAdView(ads: ads, height: height, direction: direction);
  }
}
