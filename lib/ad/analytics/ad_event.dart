import '../core/ad_enums.dart';

class AdEvent {
  final AdEventType eventType;
  final PlacementType placement;
  final String? placementLabel;
  final AdType adType;
  final AdSource source;
  final String adUnitId;
  final int? errorCode;
  final String? errorReason;
  final double? revenue;
  final String? currency;
  final DateTime timestamp;

  const AdEvent({
    required this.eventType,
    required this.placement,
    this.placementLabel,
    required this.adType,
    required this.source,
    required this.adUnitId,
    required this.timestamp,
    this.errorCode,
    this.errorReason,
    this.revenue,
    this.currency,
  });
}
