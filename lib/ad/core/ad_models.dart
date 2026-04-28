import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_enums.dart';

class PlacementAdSlot {
  final PlacementType placement;
  final Ad? ad;
  final AdSource? loadedSource;
  final AdType? loadedType;
  final String? adUnitId;
  final DateTime? loadedAt;
  final bool isLoading;
  final Object? lastError;

  const PlacementAdSlot({
    required this.placement,
    this.ad,
    this.loadedSource,
    this.loadedType,
    this.adUnitId,
    this.loadedAt,
    this.isLoading = false,
    this.lastError,
  });

  bool get hasAd => ad != null;

  PlacementAdSlot copyWith({
    Ad? ad,
    AdSource? loadedSource,
    AdType? loadedType,
    String? adUnitId,
    DateTime? loadedAt,
    bool? isLoading,
    Object? lastError,
    bool clearAd = false,
  }) {
    return PlacementAdSlot(
      placement: placement,
      ad: clearAd ? null : (ad ?? this.ad),
      loadedSource: clearAd ? null : (loadedSource ?? this.loadedSource),
      loadedType: clearAd ? null : (loadedType ?? this.loadedType),
      adUnitId: clearAd ? null : (adUnitId ?? this.adUnitId),
      loadedAt: clearAd ? null : (loadedAt ?? this.loadedAt),
      isLoading: isLoading ?? this.isLoading,
      lastError: lastError ?? this.lastError,
    );
  }
}

class AdLoadResult<TAd extends Ad> {
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
