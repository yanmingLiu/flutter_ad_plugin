import 'package:flutter/widgets.dart';

import 'ad/analytics/ad_event_reporter.dart';
import 'ad/config/ad_config_repository.dart';
import 'ad/core/ad_enums.dart';
import 'ad/service/ad_service.dart';
import 'ad/ui/native_ad_view.dart';
import 'tools/facebook_util.dart';

export 'ad/analytics/ad_event.dart';
export 'ad/analytics/ad_event_reporter.dart';
export 'ad/config/ad_config_repository.dart';
export 'ad/core/ad_config.dart';
export 'ad/core/ad_enums.dart';
export 'ad/ui/native_ad_view.dart';
export 'tools/facebook_util.dart';

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
    return AdService.instance.preload(placement);
  }

  static Future<bool> show(PlacementType placement, {String? placementLabel}) {
    return AdService.instance.show(placement, placementLabel: placementLabel);
  }

  static Future<bool> loadNative(PlacementType placement) {
    return AdService.instance.loadNative(placement);
  }

  static Object? getNativeAd(PlacementType placement) {
    return AdService.instance.getNativeAd(placement);
  }

  static Future<Object?> showNative(
    PlacementType placement, {
    String? placementLabel,
  }) {
    return AdService.instance.showNative(
      placement,
      placementLabel: placementLabel,
    );
  }

  static Widget nativeAdWidget({required Object ad, double height = 280}) {
    return NativeAdView(ad: ad, height: height);
  }
}
