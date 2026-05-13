import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../analytics/ad_event_reporter.dart';
import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';

abstract class AdTypeAdapter<TAd extends Ad> {
  AdSource get source;
  AdType get type;

  Future<AdLoadResult<TAd>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    void Function(TAd ad, AdType type, String adUnitId)? onLateAdLoaded,
  });

  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required TAd ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  });

  void dispose(TAd ad);
}
