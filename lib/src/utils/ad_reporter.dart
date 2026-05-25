import '../core/ad_enums.dart';

/// 广告事件类型，涵盖加载、展示、点击、收益、关闭等全生命周期。
enum AdEventType {
  loadRequested,
  loadSucceeded,
  loadFailed,
  show,
  showSuccess,
  showFail,
  clicked,
  income,
  close,
}

/// 广告埋点事件。
///
/// 由引擎在广告生命周期的各个节点创建，通过 [AdEventReporter] 回调给宿主。
///
/// [eventName] 是宿主调用 [show]/[preload]/[loadNative] 时必传的广告场景。
/// 用于在埋点系统中区分场景（如 `open_cold`、`open_hot`、`cold_load` 等）。
/// 插件不做任何处理，原样透传。
class AdEvent {
  final AdEventType eventType;
  final PlacementType placement;
  final String? placementLabel;
  final AdType adType;
  final AdSource source;
  final String adUnitId;
  final double? revenue; // valueMicros from AdMob onPaidEvent
  final String? currency;
  final int? errorCode;
  final String? errorReason;
  final DateTime timestamp;

  /// 宿主传入的广告场景，插件原样透传。
  final String eventName;

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
    required this.eventName,
  });

  Map<String, Object?> toJson() {
    return {
      'event_type': eventType.name,
      'placement': placement.name,
      'placement_label': placementLabel,
      'ad_type': adType.name,
      'ad_source': source.name,
      'ad_unit_id': adUnitId,
      'revenue': revenue,
      'currency': currency,
      'error_code': errorCode,
      'error_reason': errorReason,
      'timestamp': timestamp.toIso8601String(),
      'event_name': eventName,
    };
  }
}

/// 埋点上报接口，由宿主实现并注入到 [init] 中。
abstract class AdEventReporter {
  Future<void> report(AdEvent event);
}

class DefaultAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    // 默认空实现，由使用者注入具体实现
  }
}
