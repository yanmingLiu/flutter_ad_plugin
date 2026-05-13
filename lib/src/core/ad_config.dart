import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../utils/ad_logger.dart';
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
    final isFullscreen =
        placement == PlacementType.open ||
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
    if (isFullscreen) {
      return type == AdType.open ||
          type == AdType.interstitial ||
          type == AdType.rewarded;
    } else {
      return type == AdType.native;
    }
  }
}

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

    json.forEach((key, value) {
      if (globalKeys.contains(key)) return;
      if (value is! List) return;

      final placement = PlacementType(key);
      final parsed =
          value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(_parseUnitOrNull)
              .whereType<AdUnitConfig>()
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      placements[placement] = parsed;
    });

    final policyMapRaw = json['placement_policy'];
    final policyMap = (policyMapRaw is Map)
        ? Map<String, dynamic>.from(policyMapRaw)
        : <String, dynamic>{};

    // 为每个有广告单元的广告位生成 Policy
    placements.forEach((placement, units) {
      final jsonPolicy = policyMap[placement.name] is Map
          ? Map<String, dynamic>.from(policyMap[placement.name])
          : <String, dynamic>{};
      policies[placement] = _parsePolicy(placement, units, jsonPolicy);
    });

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

  PlacementPolicy _parsePolicy(
    PlacementType placement,
    List<AdUnitConfig> units,
    Map<String, dynamic> json,
  ) {
    Set<AdType>? allowedTypes;
    final allowedRaw = json['allowed_types'];
    if (allowedRaw is List) {
      allowedTypes = allowedRaw
          .whereType<String>()
          .map((e) => AdType(e))
          .toSet();
    }

    // 自动推断是否为全屏
    final bool inferredFullscreen = units.any((u) => u.type.isFullscreen);

    return PlacementPolicy(
      isFullscreen: json['is_fullscreen'] ?? inferredFullscreen,
      applySamePlacementCd: json['apply_same_placement_cd'] ?? false,
      applyDifferentPlacementCd: json['apply_different_placement_cd'] ?? false,
      contributesToGlobalCooldown:
          json['contributes_to_global_cooldown'] ?? false,
      showNotReadyToast: json['show_not_ready_toast'] ?? false,
      notReadyMsg: json['not_ready_msg'] as String?,
      allowedTypes: allowedTypes,
    );
  }
}

abstract class AdConfigRepository {
  Future<AdConfig> getConfig();
}

class DefaultAdConfigRepository implements AdConfigRepository {
  DefaultAdConfigRepository({AdConfigParser? parser})
    : _parser = parser ?? AdConfigParser();

  static const _remoteConfigKey = 'ad_config_json';

  static const Map<String, dynamic> _devConfig = {
    'load_timeout': 7,
    'same_placement_cd': 30,
    'different_placement_cd': 30,
    'open': [
      {
        'source': 'admob',
        'weight': 3,
        'type': 'open',
        'id': 'ca-app-pub-3940256099942544/5575463023',
      },
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
      {
        'source': 'admob',
        'weight': 1,
        'type': 'rewarded',
        'id': 'ca-app-pub-3940256099942544/1712485313',
      },
    ],
    'home': [
      {
        'source': 'admob',
        'weight': 1,
        'type': 'native',
        'id': 'ca-app-pub-3940256099942544/1044960115',
      },
    ],
    'message': [
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
      {
        'source': 'admob',
        'weight': 3,
        'type': 'rewarded',
        'id': 'ca-app-pub-3940256099942544/1712485313',
      },
    ],
    'placement_policy': {
      'open': {
        'apply_same_placement_cd': true,
        'apply_different_placement_cd': true,
        'contributes_to_global_cooldown': true,
      }
    }
  };

  static const Map<String, dynamic> _prodConfig = _devConfig; // 这里简化了，实际可根据需要区分

  final AdConfigParser _parser;
  AdConfig? _cached;

  @override
  Future<AdConfig> getConfig() async {
    return _cached ??= await _loadConfig();
  }

  Future<AdConfig> _loadConfig() async {
    log.d('⚙️ [config] loading');
    if (Firebase.apps.isNotEmpty) {
      final remoteJson = FirebaseRemoteConfig.instance.getString(
        _remoteConfigKey,
      );
      if (remoteJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(remoteJson);
          return _parser.parse(
            Map<String, dynamic>.from(decoded is Map ? decoded : {}),
          );
        } catch (e) {
          log.e('❌ [config] parse_fail: $e');
        }
      }
    }
    const useDevConfig = kDebugMode || kProfileMode;
    return _parser.parse(useDevConfig ? _devConfig : _prodConfig);
  }
}
