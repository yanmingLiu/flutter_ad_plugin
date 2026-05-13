import '../../tools/log_tool.dart';
import '../../tools/facebook_util.dart';
import '../core/ad_enums.dart';
import 'ad_event.dart';

abstract class AdEventReporter {
  Future<void> report(AdEvent event);
}

class DefaultAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    final placementValue = event.placementLabel ?? event.placement.name;
    log.d(
      '[ad] 👉 ${event.eventType.name} placement=$placementValue '
      'type=${event.adType.name} unit=${event.adUnitId}',
    );

    if (event.eventType == AdEventType.income) {
      final facebookValue = _adRevenueMicrosToValue(event.revenue);
      if (facebookValue != null &&
          event.currency != null &&
          event.currency!.isNotEmpty) {
        FacebookSDKUtil.logAdImpression(
          value: facebookValue,
          currency: event.currency!,
          adType: event.adType.name,
          adUnitId: event.adUnitId,
        );
      }
    }
  }

  double? _adRevenueMicrosToValue(double? valueMicros) {
    if (valueMicros == null || valueMicros <= 0) {
      return null;
    }
    return valueMicros / 1000000;
  }
}
