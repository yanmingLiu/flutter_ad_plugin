import 'package:flutter/foundation.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../utils/ad_reporter.dart';

abstract class AdTypeAdapter {
  AdSource get source;
  AdType get type;

  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    String? eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  });

  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    String? eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  });

  void dispose(Object ad);
}
