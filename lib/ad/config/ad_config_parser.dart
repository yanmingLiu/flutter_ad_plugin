import '../core/ad_config.dart';
import '../core/ad_enums.dart';

class AdConfigParser {
  AdConfig parse(Map<String, dynamic> json) {
    final placements = <PlacementType, List<AdUnitConfig>>{};
    final placementPolicies = <PlacementType, PlacementPolicyConfig>{};
    for (final placement in Placements.values) {
      placements[placement] = const [];
    }

    for (final entry in json.entries) {
      final placement = entry.key;
      final rawList = entry.value;
      if (rawList is! List) {
        continue;
      }

      final parsed =
          rawList
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(_parseUnitOrNull)
              .whereType<AdUnitConfig>()
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));
      placements[placement] = parsed;
    }

    final rawPolicies = json['placement_policy'];
    if (rawPolicies is Map) {
      for (final entry in rawPolicies.entries) {
        final placement = '${entry.key}';
        if (entry.value is! Map) continue;
        final m = Map<String, dynamic>.from(entry.value as Map);
        placementPolicies[placement] = PlacementPolicyConfig(
          isFullscreen: m['is_fullscreen'] as bool?,
          applySamePlacementCd: m['apply_same_placement_cd'] as bool?,
          applyDifferentPlacementCd: m['apply_different_placement_cd'] as bool?,
          contributesToGlobalCooldown:
              m['contributes_to_global_cooldown'] as bool?,
          showNotReadyToast: m['show_not_ready_toast'] as bool?,
        );
      }
    }

    return AdConfig(
      loadTimeoutSeconds: (json['load_timeout'] as num?)?.toInt() ?? 7,
      samePlacementCdSeconds:
          (json['same_placement_cd'] as num?)?.toInt() ?? 30,
      differentPlacementCdSeconds:
          (json['different_placement_cd'] as num?)?.toInt() ?? 30,
      placements: placements,
      placementPolicies: placementPolicies,
    );
  }

  AdUnitConfig? _parseUnitOrNull(Map<String, dynamic> json) {
    final id = (json['id'] as String?)?.trim() ?? '';
    final typeRaw = (json['type'] as String?)?.trim();
    final sourceRaw = (json['source'] as String?)?.trim();
    if (id.isEmpty || typeRaw == null || sourceRaw == null) {
      return null;
    }

    final type = parseType(typeRaw);
    final source = parseSource(sourceRaw);
    if (type == null || source == null) {
      return null;
    }

    return AdUnitConfig(
      source: source,
      weight: (json['weight'] as num?)?.toInt() ?? 0,
      type: type,
      id: id,
    );
  }

  AdType? parseType(String raw) {
    switch (raw.toLowerCase()) {
      case 'open':
        return AdType.open;
      case 'interstitial':
        return AdType.interstitial;
      case 'rewarded':
        return AdType.rewarded;
      case 'native':
        return AdType.native;
      default:
        return null;
    }
  }

  AdSource? parseSource(String raw) {
    switch (raw.toLowerCase()) {
      case 'admob':
        return AdSource.admob;
      case 'max':
        return AdSource.max;
      case 'topon':
        return AdSource.topon;
      default:
        return null;
    }
  }
}
