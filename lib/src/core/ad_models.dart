import 'ad_enums.dart';

class PlacementAdSlot {
  final PlacementType placement;

  /// 原始广告对象（可以是 AdMob 的 Ad，也可以是 MAX 的 Ad 对象）
  final Object? ad;
  final AdSource? loadedSource;
  final AdType? loadedType;
  final String? adUnitId;
  final String? cacheKey;
  final DateTime? loadedAt;
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
    this.isLoading = false,
    this.lastError,
  });

  bool get hasAd => ad != null;
}

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

class AdShowResult {
  final bool shown;
  final bool rewardEarned;
  final Object? error;

  const AdShowResult({
    required this.shown,
    this.rewardEarned = false,
    this.error,
  });

  factory AdShowResult.success({bool rewardEarned = false}) {
    return AdShowResult(shown: true, rewardEarned: rewardEarned);
  }

  factory AdShowResult.failure([Object? error]) {
    return AdShowResult(shown: false, error: error);
  }
}
