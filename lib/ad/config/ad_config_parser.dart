import '../core/ad_config.dart';
import '../core/ad_enums.dart';

class AdConfigParser {
  AdConfig parse(Map<String, dynamic> json) {
    final placements = <PlacementType, List<AdUnitConfig>>{};
    final policies = <PlacementType, PlacementPolicy>{};

    final globalKeys = {
      'load_timeout',
      'same_placement_cd',
      'different_placement_cd',
      'placement_policy',
      'preload_list',
    };

    // 解析广告位单元
    json.forEach((key, value) {
      if (globalKeys.contains(key)) return;
      if (value is! List) return;

      final placement = PlacementType(key);
      final parsed = value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(_parseUnitOrNull)
          .whereType<AdUnitConfig>()
          .toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));
      
      placements[placement] = parsed;
    });

    // 解析策略配置
    final policyMapRaw = json['placement_policy'];
    if (policyMapRaw is Map) {
      policyMapRaw.forEach((key, value) {
        if (value is Map) {
          final placement = PlacementType(key);
          policies[placement] = _parsePolicy(Map<String, dynamic>.from(value));
        }
      });
    }

    // 解析预加载列表
    final preloadListRaw = json['preload_list'];
    final List<PlacementType> preloadList = [];
    if (preloadListRaw is List) {
      for (var item in preloadListRaw) {
        if (item is String) {
          preloadList.add(PlacementType(item));
        }
      }
    }

    return AdConfig(
      loadTimeoutSeconds: (json['load_timeout'] as num?)?.toInt() ?? 7,
      samePlacementCdSeconds:
          (json['same_placement_cd'] as num?)?.toInt() ?? 30,
      differentPlacementCdSeconds:
          (json['different_placement_cd'] as num?)?.toInt() ?? 30,
      preloadList: preloadList,
      placements: placements,
      policies: policies,
    );
  }

  AdUnitConfig? _parseUnitOrNull(Map<String, dynamic> json) {
    final id = (json['id'] as String?)?.trim() ?? '';
    final typeRaw = (json['type'] as String?)?.trim();
    final sourceRaw = (json['source'] as String?)?.trim();
    if (id.isEmpty || typeRaw == null || sourceRaw == null) {
      return null;
    }

    return AdUnitConfig(
      source: AdSource(sourceRaw),
      weight: (json['weight'] as num?)?.toInt() ?? 0,
      type: AdType(typeRaw),
      id: id,
      templateType: json['template_type'] as String?,
      refreshMinutes: (json['refresh_minutes'] as num?)?.toInt(),
    );
  }

  PlacementPolicy _parsePolicy(Map<String, dynamic> json) {
    Set<AdType>? allowedTypes;
    final allowedRaw = json['allowed_types'];
    if (allowedRaw is List) {
      allowedTypes = allowedRaw.whereType<String>().map((e) => AdType(e)).toSet();
    }

    return PlacementPolicy(
      isFullscreen: json['is_fullscreen'] ?? true,
      applySamePlacementCd: json['apply_same_placement_cd'] ?? false,
      applyDifferentPlacementCd: json['apply_different_placement_cd'] ?? false,
      contributesToGlobalCooldown: json['contributes_to_global_cooldown'] ?? false,
      showNotReadyToast: json['show_not_ready_toast'] ?? false,
      notReadyMsg: json['not_ready_msg'] as String?,
      allowedTypes: allowedTypes,
    );
  }
}
