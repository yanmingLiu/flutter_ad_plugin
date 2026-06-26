import '../core/ad_enums.dart';
import '../platform/ad_callback.dart';
import '../utils/ad_reporter.dart';

/// Converts raw [AdRawCallback] instances emitted by adapters into
/// structured [AdEvent] objects for reporting.
class AdEventMapper {
  AdEvent map(
    AdRawCallback callback, {
    PlacementType? placement,
    String? placementLabel,
    required String eventName,
    AdType? adType,
    AdSource? source,
    String? adUnitId,
  }) {
    switch (callback) {
      case AdImpressionCallback(:final network):
        return AdEvent(
          eventType: AdEventType.showSuccess,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          network: network,
        );

      case AdPaidCallback(
        :final valueMicros,
        :final currencyCode,
        :final network,
      ):
        return AdEvent(
          eventType: AdEventType.income,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          revenue: valueMicros,
          currency: currencyCode,
          timestamp: DateTime.now(),
          eventName: eventName,
          network: network,
        );

      case AdClickedCallback(:final network):
        return AdEvent(
          eventType: AdEventType.clicked,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          network: network,
        );

      case AdClosedCallback(:final network):
        return AdEvent(
          eventType: AdEventType.close,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          network: network,
        );

      case AdShowedCallback(:final network):
        return AdEvent(
          eventType: AdEventType.showSuccess,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          network: network,
        );

      case AdShowFailedCallback(
        :final errorCode,
        :final errorMessage,
        :final network,
      ):
        return AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          errorCode: errorCode,
          errorReason: errorMessage,
          timestamp: DateTime.now(),
          eventName: eventName,
          network: network,
        );
    }
  }
}
