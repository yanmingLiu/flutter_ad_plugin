import 'ad_enums.dart';

class AdConfig {
  final int loadTimeoutSeconds;
  final int samePlacementCdSeconds;
  final int differentPlacementCdSeconds;
  final Map<PlacementType, List<AdUnitConfig>> placements;
  final Map<PlacementType, PlacementPolicyConfig> placementPolicies;

  const AdConfig({
    required this.loadTimeoutSeconds,
    required this.samePlacementCdSeconds,
    required this.differentPlacementCdSeconds,
    required this.placements,
    this.placementPolicies = const {},
  });

  List<AdUnitConfig> getUnits(PlacementType placement) {
    return placements[placement] ?? const [];
  }

  PlacementPolicyConfig? getPolicy(PlacementType placement) {
    return placementPolicies[placement];
  }
}

class AdUnitConfig {
  final AdSource source;
  final int weight;
  final AdType type;
  final String id;

  const AdUnitConfig({
    required this.source,
    required this.weight,
    required this.type,
    required this.id,
  });

  bool get isValid => id.isNotEmpty;
}

class PlacementPolicyConfig {
  final bool? isFullscreen;
  final bool? applySamePlacementCd;
  final bool? applyDifferentPlacementCd;
  final bool? contributesToGlobalCooldown;
  final bool? showNotReadyToast;

  const PlacementPolicyConfig({
    this.isFullscreen,
    this.applySamePlacementCd,
    this.applyDifferentPlacementCd,
    this.contributesToGlobalCooldown,
    this.showNotReadyToast,
  });
}
