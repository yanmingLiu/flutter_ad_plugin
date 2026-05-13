import 'package:flutter/widgets.dart';

import 'src/core/ad_config.dart';
import 'src/core/ad_enums.dart';
import 'src/engine/ad_engine.dart';
import 'src/ui/native_ad_view.dart';
import 'src/utils/ad_reporter.dart';
import 'src/utils/facebook_util.dart';

export 'src/core/ad_config.dart';
export 'src/core/ad_enums.dart';
export 'src/ui/native_ad_view.dart';
export 'src/utils/ad_reporter.dart';
export 'src/utils/facebook_util.dart';

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

  static Future<void> initFacebookSDK({
    required String appId,
    required String clientToken,
  }) {
    return FacebookSDKUtil.initializeFacebookSDK(
      appId: appId,
      clientToken: clientToken,
    );
  }

  static Future<bool> preload(PlacementType placement) {
    return AdEngine.instance.preload(placement);
  }

  static Future<bool> show(PlacementType placement, {String? placementLabel}) {
    return AdEngine.instance.show(placement, placementLabel: placementLabel);
  }

  static Future<bool> loadNative(PlacementType placement) {
    return AdEngine.instance.preloadNative(placement);
  }

  static Object? getNativeAd(PlacementType placement) {
    return AdEngine.instance.getNativeAd(placement);
  }

  static Widget nativeAdWidget({required Object ad, double height = 280}) {
    return NativeAdView(ad: ad, height: height);
  }
}
