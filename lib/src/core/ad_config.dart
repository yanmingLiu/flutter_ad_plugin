import 'dart:convert';

import 'ad_enums.dart';
import 'ad_policy.dart';

/// 广告配置的运行时模型，由 [AdConfigParser] 从 JSON 解析生成。
///
/// 所有广告行为（超时、CD、缓存数量、策略）均由本配置驱动。
class AdConfig {
  final int loadTimeoutSeconds;
  final int rewardedLoadTimeoutSeconds;
  final int adCdSeconds;
  final List<PlacementType> commonPlacements;
  final PlacementType? highValuePlacement;
  final Map<PlacementType, List<AdUnitConfig>> placements;
  final Map<PlacementType, PlacementPolicy> policies;

  const AdConfig({
    required this.loadTimeoutSeconds,
    this.rewardedLoadTimeoutSeconds = 7,
    required this.adCdSeconds,
    this.commonPlacements = const [],
    this.highValuePlacement,
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

  int fullscreenCacheSizeFor(PlacementType placement, {int minimum = 1}) {
    final policy = getPolicy(placement);
    return _cacheSizeFor(
      placement,
      minimum: minimum,
      include: (unit) =>
          unit.type.isFullscreen ||
          (policy.isFullscreen && unit.type == AdType.native),
    );
  }

  int nativeCacheSizeFor(PlacementType placement, {int minimum = 1}) {
    return _cacheSizeFor(
      placement,
      minimum: minimum,
      include: (unit) => unit.type.isNative,
    );
  }

  int _cacheSizeFor(
    PlacementType placement, {
    required int minimum,
    required bool Function(AdUnitConfig unit) include,
  }) {
    var size = minimum;
    for (final unit in getUnits(placement).where(include)) {
      if (unit.poolSize > size) {
        size = unit.poolSize;
      }
    }
    return size;
  }

  Duration loadTimeoutFor(AdUnitConfig unit) {
    return Duration(
      seconds:
          unit.loadTimeoutSeconds ??
          (unit.type == AdType.rewarded ||
                  unit.type == AdType.rewardedInterstitial
              ? rewardedLoadTimeoutSeconds
              : loadTimeoutSeconds),
    );
  }

  PlacementPolicy getPolicy(PlacementType placement) {
    return policies[placement] ??
        PlacementPolicy.defaultPolicy(this, placement);
  }

  Iterable<PlacementType> get configuredPlacements => placements.keys;

  bool hasPlacement(PlacementType placement) {
    return getUnits(placement).isNotEmpty;
  }
}

class AdUnitConfig {
  final AdSource source;
  final int weight;
  final AdType type;
  final String id;
  final String cacheKey;
  final String? templateType;
  final String? factoryId;
  final String? bannerMode;
  final int? loadTimeoutSeconds;
  final int poolSize;

  const AdUnitConfig({
    required this.source,
    required this.weight,
    required this.type,
    required this.id,
    String? cacheKey,
    this.templateType,
    this.factoryId,
    this.bannerMode,
    this.loadTimeoutSeconds,
    this.poolSize = 1,
  }) : cacheKey = cacheKey ?? id;

  bool get isValid => id.isNotEmpty;
}

class AdConfigParser {
  AdConfig parse(Map<String, dynamic> json) {
    final placements = <PlacementType, List<AdUnitConfig>>{};

    json.forEach((key, value) {
      if (value is! List) {
        return;
      }

      final items = value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (items.isEmpty || !items.every(_looksLikeAdUnit)) {
        return;
      }

      final placement = PlacementType(key);
      final parsed = items.expand(_parseUnits).toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));

      if (parsed.isNotEmpty) {
        placements[placement] = parsed;
      }
    });

    final commonList = _parsePlacementList(
      json['common_placements'] ?? json['common_placement'],
    );
    final highValueRaw = json['high_value_placement'];
    final highValuePlacement = highValueRaw is String && highValueRaw.isNotEmpty
        ? PlacementType(highValueRaw)
        : placements.containsKey(const PlacementType('level_h'))
        ? const PlacementType('level_h')
        : null;

    return AdConfig(
      loadTimeoutSeconds: (json['load_timeout'] as num?)?.toInt() ?? 7,
      rewardedLoadTimeoutSeconds:
          (json['rewarded_load_timeout'] as num?)?.toInt() ??
          (json['load_timeout'] as num?)?.toInt() ??
          7,
      adCdSeconds: (json['ad_cd'] as num?)?.toInt() ?? 30,
      commonPlacements: commonList.isEmpty
          ? const [PlacementType('behavior'), PlacementType('behavior2')]
          : commonList,
      highValuePlacement: highValuePlacement,
      placements: placements,
    );
  }

  bool _looksLikeAdUnit(Map<String, dynamic> json) {
    final hasSource = _stringValue(json['source'] ?? json['ad_source']) != null;
    final hasType = _stringValue(json['type'] ?? json['ad_type']) != null;
    final hasId = _parseAdUnitIds(json).isNotEmpty;
    return hasSource && hasType && hasId;
  }

  List<PlacementType> _parsePlacementList(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return [PlacementType(raw.trim())];
    }
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map(PlacementType.new)
        .toList();
  }

  Iterable<AdUnitConfig> _parseUnits(Map<String, dynamic> json) sync* {
    final ids = _parseAdUnitIds(json);
    final typeRaw = _stringValue(json['type'] ?? json['ad_type']);
    final sourceRaw = _stringValue(json['source'] ?? json['ad_source']);
    if (ids.isEmpty || typeRaw == null || sourceRaw == null) {
      return;
    }

    for (var index = 0; index < ids.length; index++) {
      final id = ids[index];
      yield AdUnitConfig(
        source: AdSource(sourceRaw),
        weight:
            (json['weight'] as num?)?.toInt() ??
            (json['ad_weight'] as num?)?.toInt() ??
            0,
        type: AdType(typeRaw),
        id: id,
        cacheKey: '${sourceRaw}_${typeRaw}_${index}_$id',
        templateType: json['template_type'] as String?,
        factoryId: _stringValue(json['factory_id']),
        bannerMode: _stringValue(json['banner_mode']),
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

    addId(json['id'] ?? json['ad_id']);
    addId(json['ad_id2']);

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

  String? _stringValue(Object? value) {
    if (value is! String) {
      return null;
    }
    final text = value.trim();
    return text.isEmpty ? null : text;
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
    Map<PlacementType, PlacementPolicy> placementPolicies = const {},
  }) : _parser = parser ?? AdConfigParser(),
       _localConfig = _parseLocalConfig(localConfig, localConfigJson),
       _placementPolicies = Map<PlacementType, PlacementPolicy>.unmodifiable(
         placementPolicies,
       );

  final AdConfigParser _parser;
  final Map<String, dynamic> _localConfig;
  final Map<PlacementType, PlacementPolicy> _placementPolicies;
  AdConfig? _cached;

  @override
  Future<AdConfig> getConfig() async {
    return _cached ??= _withPlacementPolicies(
      _parser.parse(Map<String, dynamic>.from(_localConfig)),
    );
  }

  AdConfig _withPlacementPolicies(AdConfig config) {
    if (_placementPolicies.isEmpty) {
      return config;
    }
    return AdConfig(
      loadTimeoutSeconds: config.loadTimeoutSeconds,
      rewardedLoadTimeoutSeconds: config.rewardedLoadTimeoutSeconds,
      adCdSeconds: config.adCdSeconds,
      commonPlacements: config.commonPlacements,
      highValuePlacement: config.highValuePlacement,
      placements: config.placements,
      policies: _placementPolicies,
    );
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
}
