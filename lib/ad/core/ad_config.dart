import 'ad_enums.dart';

class AdConfig {
  final int loadTimeoutSeconds;
  final int samePlacementCdSeconds;
  final int differentPlacementCdSeconds;
  final List<PlacementType> preloadList;
  final Map<PlacementType, List<AdUnitConfig>> placements;
  final Map<PlacementType, PlacementPolicy> policies;

  const AdConfig({
    required this.loadTimeoutSeconds,
    required this.samePlacementCdSeconds,
    required this.differentPlacementCdSeconds,
    this.preloadList = const [],
    required this.placements,
    this.policies = const {},
  });

  List<AdUnitConfig> getUnits(PlacementType placement) {
    return placements[placement] ?? const [];
  }

  PlacementPolicy getPolicy(PlacementType placement) {
    return policies[placement] ?? PlacementPolicy.defaultPolicy(placement);
  }
}

class AdUnitConfig {
  final AdSource source;
  final int weight;
  final AdType type;
  final String id;
  final String? templateType;
  final int? refreshMinutes;

  const AdUnitConfig({
    required this.source,
    required this.weight,
    required this.type,
    required this.id,
    this.templateType,
    this.refreshMinutes,
  });

  bool get isValid => id.isNotEmpty;
}

class PlacementPolicy {
  final bool isFullscreen;
  final bool applySamePlacementCd;
  final bool applyDifferentPlacementCd;
  final bool contributesToGlobalCooldown;
  final bool showNotReadyToast;
  final String? notReadyMsg;
  /// 该广告位允许的广告类型（如果为空，则根据 isFullscreen 决定默认值）
  final Set<AdType>? allowedTypes;

  const PlacementPolicy({
    required this.isFullscreen,
    required this.applySamePlacementCd,
    required this.applyDifferentPlacementCd,
    required this.contributesToGlobalCooldown,
    required this.showNotReadyToast,
    this.notReadyMsg,
    this.allowedTypes,
  });

  factory PlacementPolicy.defaultPolicy(PlacementType placement) {
    // 默认规则：根据常见的命名猜测是否是全屏
    final isFullscreen = placement == PlacementType.open || 
                         placement.name.toLowerCase().contains('chat') ||
                         placement.name.toLowerCase().contains('video');
                         
    return PlacementPolicy(
      isFullscreen: isFullscreen,
      applySamePlacementCd: false,
      applyDifferentPlacementCd: false,
      contributesToGlobalCooldown: false,
      showNotReadyToast: false,
    );
  }

  bool supports(AdType type) {
    if (allowedTypes != null) {
      return allowedTypes!.contains(type);
    }
    // 默认逻辑
    if (isFullscreen) {
      return type == AdType.open || type == AdType.interstitial || type == AdType.rewarded;
    } else {
      return type == AdType.native;
    }
  }
}
