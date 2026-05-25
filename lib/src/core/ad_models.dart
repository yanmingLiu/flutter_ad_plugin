import 'ad_enums.dart';

class NativeAdAttribution {
  NativeAdAttribution({
    required this.placement,
    this.placementLabel,
    required this.eventName,
  });

  PlacementType placement;
  String? placementLabel;
  String eventName;
}

/// 广告缓存池中的单个广告槽位。
///
/// [cacheKey] 用于去重，由配置解析时根据 source + type + index + id 生成，
/// 确保同一广告位配置多个 ID 时不会重复缓存同一个广告。
class PlacementAdSlot {
  final PlacementType placement;

  /// 原始广告对象（AdMob Ad / MAX Ad 等，类型抹平为 Object）
  final Object? ad;
  final AdSource? loadedSource;
  final AdType? loadedType;
  final String? adUnitId;

  /// 唯一标识，用于防止重复缓存
  final String? cacheKey;
  final DateTime? loadedAt;
  final NativeAdAttribution? nativeAttribution;
  final bool isLoading;
  final Object? lastError;

  const PlacementAdSlot({
    required this.placement,
    this.ad,
    this.loadedSource,
    this.loadedType,
    this.adUnitId,
    this.cacheKey,
    this.loadedAt,
    this.nativeAttribution,
    this.isLoading = false,
    this.lastError,
  });

  bool get hasAd => ad != null;
}

/// 广告缓存池，一个 placement 可以缓存多个广告。
///
/// 当 JSON 中一个 placement 通过 id/id2/ids 配置了多个广告单元 ID 时，
/// [slots] 会包含对应的多个 [PlacementAdSlot]。
class PlacementAdPool {
  final PlacementType placement;
  final List<PlacementAdSlot> slots;
  final bool isLoading;
  final Object? lastError;

  const PlacementAdPool({
    required this.placement,
    this.slots = const [],
    this.isLoading = false,
    this.lastError,
  });

  bool get hasAd => slots.isNotEmpty;
  int get count => slots.length;
  Object? get firstAd => slots.isEmpty ? null : slots.first.ad;

  List<Object> get ads =>
      slots.map((slot) => slot.ad).whereType<Object>().toList();
}

/// 广告加载结果。
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

/// 广告展示结果。
///
/// [shown] 表示是否成功展示。
class AdShowResult {
  final bool shown;
  final Object? error;

  const AdShowResult({required this.shown, this.error});

  factory AdShowResult.success() {
    return const AdShowResult(shown: true);
  }

  factory AdShowResult.failure([Object? error]) {
    return AdShowResult(shown: false, error: error);
  }
}
