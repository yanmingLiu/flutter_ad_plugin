/// 广告位类型（使用类包装 String 以支持动态扩展）
class PlacementType {
  final String name;
  const PlacementType(this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlacementType &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// 广告形式（使用类包装 String 以支持动态扩展）
class AdType {
  final String name;
  const AdType(this.name);

  static const open = AdType('open');
  static const interstitial = AdType('interstitial');
  static const rewarded = AdType('rewarded');
  static const rewardedInterstitial = AdType('rewarded_interstitial');
  static const native = AdType('native');
  static const doubleNative = AdType('double_native');
  static const banner = AdType('banner');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdType && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  bool get isFullscreen =>
      this == open ||
      this == interstitial ||
      this == rewarded ||
      this == rewardedInterstitial;

  bool get isNative => this == native || this == doubleNative;

  bool get isDoubleNative => this == doubleNative;

  bool get isBanner => this == banner;

  @override
  String toString() => name;
}

/// 广告来源（使用类包装 String 以支持动态扩展）
class AdSource {
  final String name;
  const AdSource(this.name);

  static const admob = AdSource('admob');
  static const max = AdSource('max');
  static const topon = AdSource('topon');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdSource &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

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

  /// SDK-specific options interpreted by the owning platform package.
  ///
  /// Core never reads these values. Examples include MAX scene names and
  /// TopOn placement/layout identifiers. Keeping them here avoids adding
  /// platform-specific fields to the shared config model.
  final Map<String, Object?> options;

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
    this.options = const {},
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
        options: _parseOptions(json),
      );
    }
  }

  Map<String, Object?> _parseOptions(Map<String, dynamic> json) {
    final raw = json['options'];
    if (raw is! Map) return const {};
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
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

/// Attribution info stored alongside cached ads.
///
/// Tracks which placement and event context an ad belongs to,
/// so that later lifecycle callbacks (click, impression, paid)
/// can be correctly attributed.
///
/// ---
/// 缓存在广告旁边的归因信息，记录广告所属的 placement 和事件上下文，
/// 使后续生命周期回调（click、impression、paid）能被正确归因。
class AdAttribution {
  PlacementType placement;
  String eventName;
  Map<String, dynamic>? extras;

  AdAttribution({
    required this.placement,
    required this.eventName,
    this.extras,
  });
}

/// Sealed hierarchy for ad slot states in cache.
///
/// Replaces the old [PlacementAdSlot] with nullable-everything pattern.
/// Use pattern matching or `switch` to handle each state exhaustively.
///
/// ---
/// 广告缓存槽位的 Sealed 状态层级，替代旧的 nullable-everything 模式。
/// 使用模式匹配或 `switch` 穷尽处理每种状态。
sealed class AdSlotState {
  final PlacementType placement;

  const AdSlotState({required this.placement});
}

/// A successfully loaded and cached ad slot.
class AdSlotLoaded extends AdSlotState {
  final Object ad;
  final AdSource source;
  final AdType type;
  final String adUnitId;
  final String cacheKey;
  final DateTime loadedAt;
  final AdAttribution? attribution;

  AdSlotLoaded({
    required super.placement,
    required this.ad,
    required this.source,
    required this.type,
    required this.adUnitId,
    required this.cacheKey,
    required this.loadedAt,
    this.attribution,
  });
}

/// A failed ad load attempt, recorded to track errors.
class AdSlotFailed extends AdSlotState {
  final String? cacheKey;
  final Object? error;

  AdSlotFailed({required super.placement, this.cacheKey, this.error});
}

/// Ad load result returned by fullscreen `load` and inline `prepare`.
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

/// Ad show result returned by [FullscreenAdAdapter.show].
class AdShowResult {
  final bool shown;
  final PlacementType? requestedPlacement;
  final PlacementType? shownPlacement;
  final AdSource? source;
  final AdType? type;
  final String? adUnitId;
  final String? errorReason;
  final Object? error;

  const AdShowResult({
    required this.shown,
    this.requestedPlacement,
    this.shownPlacement,
    this.source,
    this.type,
    this.adUnitId,
    this.errorReason,
    this.error,
  });

  String? get requestedPlacementName => requestedPlacement?.name;
  String? get shownPlacementName => shownPlacement?.name;
  String? get typeName => type?.name;
  String? get sourceName => source?.name;

  factory AdShowResult.success({
    PlacementType? requestedPlacement,
    PlacementType? shownPlacement,
    AdSource? source,
    AdType? type,
    String? adUnitId,
  }) => AdShowResult(
    shown: true,
    requestedPlacement: requestedPlacement,
    shownPlacement: shownPlacement,
    source: source,
    type: type,
    adUnitId: adUnitId,
  );

  factory AdShowResult.failure({
    Object? error,
    PlacementType? requestedPlacement,
    PlacementType? shownPlacement,
    AdSource? source,
    AdType? type,
    String? adUnitId,
    String? errorReason,
  }) => AdShowResult(
    shown: false,
    requestedPlacement: requestedPlacement,
    shownPlacement: shownPlacement,
    source: source,
    type: type,
    adUnitId: adUnitId,
    errorReason: errorReason,
    error: error,
  );
}

/// Result of a multi-ad sequence. Each attempted cached ad has one entry.
class AdSequenceShowResult {
  final PlacementType requestedPlacement;
  final List<AdShowResult> results;
  final String? errorReason;

  const AdSequenceShowResult({
    required this.requestedPlacement,
    this.results = const [],
    this.errorReason,
  });

  bool get shown => results.any((result) => result.shown);
  int get shownCount => results.where((result) => result.shown).length;
  String get requestedPlacementName => requestedPlacement.name;
}

/// Display policy for a single placement.
///
/// Policies not provided fall back to [PlacementPolicy.defaultPolicy].
///
/// ---
/// 单个广告位的展示策略。未配置时使用默认策略。
class PlacementPolicy {
  /// Whether this placement enters the fullscreen show path.
  final bool isFullscreen;

  /// Whether `onAdNotReady` is triggered when no ad is cached.
  final bool showNotReadyToast;

  /// Custom message for `onAdNotReady` callback.
  final String? notReadyMsg;

  /// Allowlist of [AdType] values this placement accepts.
  final Set<AdType>? allowedTypes;

  const PlacementPolicy({
    required this.isFullscreen,
    this.showNotReadyToast = false,
    this.notReadyMsg,
    this.allowedTypes,
  });

  /// Creates a sensible default policy based on the placement configuration.
  factory PlacementPolicy.defaultPolicy(
    AdConfig config,
    PlacementType placement,
  ) {
    final isSharedFullscreenPlacement =
        config.commonPlacements.contains(placement) ||
        config.highValuePlacement == placement;
    return PlacementPolicy(
      isFullscreen:
          isSharedFullscreenPlacement ||
          config.getUnits(placement).any((unit) => unit.type.isFullscreen),
    );
  }

  /// Whether [type] is allowed to be shown in this placement.
  bool supports(AdType type) {
    if (allowedTypes != null) {
      return allowedTypes!.contains(type);
    }
    if (isFullscreen) {
      return type.isFullscreen || type.isNative;
    } else {
      return type.isNative || type.isBanner;
    }
  }
}

/// 广告事件类型，涵盖加载、展示、点击、收益、关闭等全生命周期。
enum AdEventType {
  loadRequested,
  loadSucceeded,
  loadFailed,
  show,
  showSuccess,
  showFail,
  clicked,
  income,
  close,
  reward,
}

/// 广告埋点事件。
///
/// 由引擎在广告生命周期的各个节点创建，通过 [AdEventReporter] 回调给宿主。
///
/// [eventName] 是宿主调用 [show]/[preload]/[loadNative] 时必传的广告场景。
/// 用于在埋点系统中区分场景（如 `open_cold`、`open_hot`、`cold_load` 等）。
/// 插件不做任何处理，原样透传。
class AdEvent {
  final AdEventType? eventType;

  /// 发起展示调用的业务广告位；加载事件和无替换展示时可为空。
  final PlacementType? requestedPlacement;

  /// 实际加载或展示的缓存广告位。
  final PlacementType? placement;
  final AdType? adType;
  final AdSource? source;
  final String? adUnitId;
  final double? revenue; // valueMicros from AdMob onPaidEvent
  final String? currency;
  final int? rewardAmount;
  final String? rewardLabel;
  final int? errorCode;
  final String? errorReason;
  final DateTime? timestamp;

  /// 宿主传入的广告场景，插件原样透传。
  final String? eventName;

  /// 宿主调用展示/加载时传入的业务自定义参数（如 uid、linkid 等），插件原样透传。
  final Map<String, dynamic>? extras;

  final String? network;

  AdEvent({
    this.eventType,
    this.requestedPlacement,
    this.placement,
    this.adType,
    this.source,
    this.adUnitId,
    this.revenue,
    this.currency,
    this.rewardAmount,
    this.rewardLabel,
    this.errorCode,
    this.errorReason,
    this.timestamp,
    this.eventName,
    this.extras,
    this.network,
  });

  String? get requestedPlacementName => requestedPlacement?.name;
  String? get placementName => placement?.name;
  String? get adTypeName => adType?.name;
  String? get sourceName => source?.name;

  Map<String, Object?> toJson() {
    return {
      'event_type': eventType?.name,
      'requested_placement': requestedPlacement?.name,
      'placement': placement?.name,
      'ad_type': adType?.name,
      'ad_source': source?.name,
      'ad_unit_id': adUnitId,
      'revenue': revenue,
      'currency': currency,
      'reward_amount': rewardAmount,
      'reward_label': rewardLabel,
      'error_code': errorCode,
      'error_reason': errorReason,
      'timestamp': timestamp?.toIso8601String(),
      'event_name': eventName,
      'extras': extras,
      'network': network,
    };
  }
}

/// 埋点上报接口，由宿主实现并注入到 [init] 中。
abstract class AdEventReporter {
  Future<void> report(AdEvent event);
}

/// 广告未准备好时回调给宿主的事件。
///
/// 插件只负责给出上下文和建议文案，是否弹 toast/snackbar/dialog 由宿主决定。
class AdNotReadyEvent {
  const AdNotReadyEvent({
    required this.requestedPlacement,
    required this.showPlacement,
    required this.eventName,
    required this.message,
  });

  final String requestedPlacement;
  final String showPlacement;
  final String eventName;
  final String message;
}

typedef AdNotReadyCallback = void Function(AdNotReadyEvent event);
