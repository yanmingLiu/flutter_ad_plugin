import 'package:flutter/widgets.dart';

import '../core/ad_enums.dart';

/// Tracks clicks reported by a loaded native ad.
abstract interface class NativeAdClickTracker {
  bool hasClicked(Object ad);
  void addClickListener(Object ad, VoidCallback listener);
  void removeClickListener(Object ad, VoidCallback listener);
}

/// Host-provided renderer for fullscreen native ads.
typedef FullscreenNativeAdPresenter =
    Future<bool> Function({
      required BuildContext context,
      required PlacementType placement,
      required String eventName,
      required Object ad,
      required NativeAdClickTracker? clickTracker,
      required int closePassThroughPercent,
      required VoidCallback onClosed,
    });
