import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../utils/ad_logger.dart';
import 'ad_enums.dart';

/// 广告配置的运行时模型，由 [AdConfigParser] 从 JSON 解析生成。
///
/// 所有广告行为（超时、CD、缓存数量、策略）均由本配置驱动。
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

  int cacheSizeFor(PlacementType placement, {int minimum = 1}) {
    var size = minimum;
    for (final unit in getUnits(placement)) {
      if (unit.poolSize > size) {
        size = unit.poolSize;
      }
    }
    return size;
  }

  Duration loadTimeoutFor(AdUnitConfig unit) {
    return Duration(seconds: unit.loadTimeoutSeconds ?? loadTimeoutSeconds);
  }

  PlacementPolicy getPolicy(PlacementType placement) {
    return policies[placement] ??
        PlacementPolicy.defaultPolicy(this, placement);
  }
}

class AdUnitConfig {
  final AdSource source;
  final int weight;
  final AdType type;
  final String id;
  final String cacheKey;
  final String? templateType;
  final int? refreshMinutes;
  final int? loadTimeoutSeconds;
  final int poolSize;

  const AdUnitConfig({
    required this.source,
    required this.weight,
    required this.type,
    required this.id,
    String? cacheKey,
    this.templateType,
    this.refreshMinutes,
    this.loadTimeoutSeconds,
    this.poolSize = 1,
  }) : cacheKey = cacheKey ?? id;

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

  factory PlacementPolicy.defaultPolicy(
    AdConfig config,
    PlacementType placement,
  ) {
    return PlacementPolicy(
      isFullscreen: config
          .getUnits(placement)
          .any((unit) => unit.type.isFullscreen),
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
      if (globalKeys.contains(key)) {
        return;
      }
      if (value is! List) {
        return;
      }

      final placement = PlacementType(key);
      final parsed =
          value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .expand(_parseUnits)
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

  Iterable<AdUnitConfig> _parseUnits(Map<String, dynamic> json) sync* {
    final ids = _parseAdUnitIds(json);
    final typeRaw = (json['type'] as String?)?.trim();
    final sourceRaw = (json['source'] as String?)?.trim();
    if (ids.isEmpty || typeRaw == null || sourceRaw == null) {
      return;
    }

    for (var index = 0; index < ids.length; index++) {
      final id = ids[index];
      yield AdUnitConfig(
        source: AdSource(sourceRaw),
        weight: (json['weight'] as num?)?.toInt() ?? 0,
        type: AdType(typeRaw),
        id: id,
        cacheKey: '${sourceRaw}_${typeRaw}_${index}_$id',
        templateType: json['template_type'] as String?,
        refreshMinutes: (json['refresh_minutes'] as num?)?.toInt(),
        loadTimeoutSeconds: (json['load_timeout'] as num?)?.toInt(),
        poolSize: ids.length,
      );
    }
  }

  List<String> _parseAdUnitIds(Map<String, dynamic> json) {
    final ids = <String>[];

    void addId(Object? value) {
      if (value is! String) {
        return;
      }
      final id = value.trim();
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }

    addId(json['id']);

    final idsRaw = json['ids'];
    if (idsRaw is List) {
      for (final id in idsRaw) {
        addId(id);
      }
    }

    final numberedKeys =
        json.keys
            .whereType<String>()
            .where((key) => RegExp(r'^id\d+$').hasMatch(key))
            .toList()
          ..sort((a, b) {
            final aIndex = int.tryParse(a.substring(2)) ?? 0;
            final bIndex = int.tryParse(b.substring(2)) ?? 0;
            return aIndex.compareTo(bIndex);
          });

    for (final key in numberedKeys) {
      addId(json[key]);
    }

    return ids;
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
  DefaultAdConfigRepository({
    AdConfigParser? parser,
    Map<String, dynamic> localConfig = const <String, dynamic>{},
    String? localConfigJson,
    String remoteConfigKey = _defaultRemoteConfigKey,
  }) : _parser = parser ?? AdConfigParser(),
       _localConfig = _parseLocalConfig(localConfig, localConfigJson),
       _remoteConfigKey = remoteConfigKey;

  static const _defaultRemoteConfigKey = 'ad_config_json';

  final AdConfigParser _parser;
  final Map<String, dynamic> _localConfig;
  final String _remoteConfigKey;
  StreamSubscription<RemoteConfigUpdate>? _remoteConfigSubscription;
  AdConfig? _cached;

  @override
  Future<AdConfig> getConfig() async {
    return _cached ??= await _loadConfig();
  }

  static Map<String, dynamic> _parseLocalConfig(
    Map<String, dynamic> localConfig,
    String? localConfigJson,
  ) {
    final rawJson = localConfigJson?.trim();
    if (rawJson == null || rawJson.isEmpty) {
      return Map<String, dynamic>.from(localConfig);
    }

    final decoded = jsonDecode(rawJson);
    return Map<String, dynamic>.from(decoded is Map ? decoded : {});
  }

  Future<AdConfig> _loadConfig() async {
    log.d('⚙️ [config] loading');
    if (Firebase.apps.isNotEmpty) {
      final remoteConfig = FirebaseRemoteConfig.instance;
      _startRemoteConfigListener(remoteConfig);
      await _ensureRemoteInitialized(remoteConfig);

      final remoteAdConfig = _parseRemoteConfig(
        remoteConfig.getString(_remoteConfigKey),
      );
      if (remoteAdConfig != null) {
        return remoteAdConfig;
      }

      unawaited(_fetchAndCacheRemoteConfig(remoteConfig));
    }

    log.d('⚙️ [config] fallback_local');
    return _parser.parse(Map<String, dynamic>.from(_localConfig));
  }

  Future<void> _ensureRemoteInitialized(
    FirebaseRemoteConfig remoteConfig,
  ) async {
    try {
      await remoteConfig.ensureInitialized();
    } catch (e) {
      log.e('❌ [config] remote_init_fail: $e');
    }
  }

  Future<void> _fetchAndCacheRemoteConfig(
    FirebaseRemoteConfig remoteConfig,
  ) async {
    try {
      await remoteConfig.fetchAndActivate();
      final remoteAdConfig = _parseRemoteConfig(
        remoteConfig.getString(_remoteConfigKey),
      );
      if (remoteAdConfig != null) {
        _cached = remoteAdConfig;
        log.d('⚙️ [config] remote_cached');
      }
    } catch (e) {
      log.e('❌ [config] remote_fetch_fail: $e');
    }
  }

  void _startRemoteConfigListener(FirebaseRemoteConfig remoteConfig) {
    if (_remoteConfigSubscription != null) {
      return;
    }

    try {
      _remoteConfigSubscription = remoteConfig.onConfigUpdated.listen(
        (update) async {
          if (!update.updatedKeys.contains(_remoteConfigKey)) {
            return;
          }

          try {
            await remoteConfig.activate();
            final remoteAdConfig = _parseRemoteConfig(
              remoteConfig.getString(_remoteConfigKey),
            );
            if (remoteAdConfig != null) {
              _cached = remoteAdConfig;
              log.d('⚙️ [config] remote_updated');
            }
          } catch (e) {
            log.e('❌ [config] remote_update_fail: $e');
          }
        },
        onError: (Object e) {
          log.e('❌ [config] remote_listener_error: $e');
        },
      );
    } catch (e) {
      log.e('❌ [config] remote_listener_fail: $e');
    }
  }

  AdConfig? _parseRemoteConfig(String rawJson) {
    if (rawJson.trim().isEmpty) {
      log.d('⚙️ [config] remote_empty');
      return null;
    }

    try {
      final decoded = jsonDecode(rawJson);
      return _parser.parse(
        Map<String, dynamic>.from(decoded is Map ? decoded : {}),
      );
    } catch (e) {
      log.e('❌ [config] remote_parse_fail: $e');
      return null;
    }
  }
}
