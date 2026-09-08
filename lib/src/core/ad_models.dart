import 'ad_enums.dart';

/// Attribution info stored alongside cached ads.
///
/// Tracks which placement and event context an ad belongs to,
/// so that later lifecycle callbacks (click, impression, paid)
/// can be correctly attributed.
///
/// ---
/// 缓存在广告旁边的归因信息，记录广告所属的 placement 和事件上下文，
/// 使后续生命周期回调（click、impression、paid）能被正确归因。
class AdAttribution {
  PlacementType placement;
  String eventName;

  AdAttribution({required this.placement, required this.eventName});
}

/// Sealed hierarchy for ad slot states in cache.
///
/// Replaces the old [PlacementAdSlot] with nullable-everything pattern.
/// Use pattern matching or `switch` to handle each state exhaustively.
///
/// ---
/// 广告缓存槽位的 Sealed 状态层级，替代旧的 nullable-everything 模式。
/// 使用模式匹配或 `switch` 穷尽处理每种状态。
sealed class AdSlotState {
  final PlacementType placement;

  const AdSlotState({required this.placement});
}

/// A successfully loaded and cached ad slot.
class AdSlotLoaded extends AdSlotState {
  final Object ad;
  final AdSource source;
  final AdType type;
  final String adUnitId;
  final String cacheKey;
  final DateTime loadedAt;
  final AdAttribution? attribution;

  AdSlotLoaded({
    required super.placement,
    required this.ad,
    required this.source,
    required this.type,
    required this.adUnitId,
    required this.cacheKey,
    required this.loadedAt,
    this.attribution,
  });
}

/// A failed ad load attempt, recorded to track errors.
class AdSlotFailed extends AdSlotState {
  final String? cacheKey;
  final Object? error;

  AdSlotFailed({required super.placement, this.cacheKey, this.error});
}

/// Ad load result returned by [AdTypeAdapter.load].
class AdLoadResult<TAd extends Object> {
  final TAd? ad;
  final AdType type;
  final String adUnitId;
  final Object? error;

  const AdLoadResult.success({
    required this.ad,
    required this.type,
    required this.adUnitId,
  }) : error = null;

  const AdLoadResult.failure({
    required this.type,
    required this.adUnitId,
    required this.error,
  }) : ad = null;

  bool get isSuccess => ad != null;
}

/// Ad show result returned by [AdTypeAdapter.show].
class AdShowResult {
  final bool shown;
  final PlacementType? requestedPlacement;
  final PlacementType? shownPlacement;
  final AdSource? source;
  final AdType? type;
  final String? adUnitId;
  final String? errorReason;
  final Object? error;

  const AdShowResult({
    required this.shown,
    this.requestedPlacement,
    this.shownPlacement,
    this.source,
    this.type,
    this.adUnitId,
    this.errorReason,
    this.error,
  });

  factory AdShowResult.success({
    PlacementType? requestedPlacement,
    PlacementType? shownPlacement,
    AdSource? source,
    AdType? type,
    String? adUnitId,
  }) => AdShowResult(
    shown: true,
    requestedPlacement: requestedPlacement,
    shownPlacement: shownPlacement,
    source: source,
    type: type,
    adUnitId: adUnitId,
  );

  factory AdShowResult.failure({
    Object? error,
    PlacementType? requestedPlacement,
    PlacementType? shownPlacement,
    AdSource? source,
    AdType? type,
    String? adUnitId,
    String? errorReason,
  }) => AdShowResult(
    shown: false,
    requestedPlacement: requestedPlacement,
    shownPlacement: shownPlacement,
    source: source,
    type: type,
    adUnitId: adUnitId,
    errorReason: errorReason,
    error: error,
  );
}
