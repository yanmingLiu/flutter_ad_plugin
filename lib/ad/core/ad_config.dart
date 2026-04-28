import 'ad_enums.dart';

class AdConfig {
  final int loadTimeoutSeconds;
  final int samePlacementCdSeconds;
  final int differentPlacementCdSeconds;
  final Map<PlacementType, List<AdUnitConfig>> placements;

  const AdConfig({
    required this.loadTimeoutSeconds,
    required this.samePlacementCdSeconds,
    required this.differentPlacementCdSeconds,
    required this.placements,
  });

  List<AdUnitConfig> getUnits(PlacementType placement) {
    return placements[placement] ?? const [];
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
