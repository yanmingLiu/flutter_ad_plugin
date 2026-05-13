import '../core/ad_enums.dart';

enum AdEventType {
  loadRequested,
  loadSucceeded,
  loadFailed,
  show,
  showSuccess,
  clicked,
  income,
  close,
  rewardEarned,
  showFail,
  blockedByGuard,
}

class AdEvent {
  final AdEventType eventType;
  final PlacementType placement;
  final String? placementLabel;
  final AdType adType;
  final AdSource source;
  final String adUnitId;
  final double? revenue; // valueMicros from AdMob
  final String? currency;
  final int? errorCode;
  final String? errorReason;
  final DateTime timestamp;

  AdEvent({
    required this.eventType,
    required this.placement,
    this.placementLabel,
    required this.adType,
    required this.source,
    required this.adUnitId,
    this.revenue,
    this.currency,
    this.errorCode,
    this.errorReason,
    required this.timestamp,
  });
}

abstract class AdEventReporter {
  Future<void> report(AdEvent event);
}

class DefaultAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    // 默认空实现，由使用者注入具体实现
  }
}
