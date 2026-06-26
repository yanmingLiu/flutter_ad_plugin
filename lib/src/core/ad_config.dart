import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'ad_enums.dart';

/// Corner position for the close button in the fullscreen native ad overlay.
///
/// ---
/// 全屏原生广告关闭按钮的角位枚举。
enum AdCloseButtonPosition {
  /// Top-right corner (default).
  ///
  /// 右上角（默认）。
  topRight,

  /// Top-left corner.
  ///
  /// 左上角。
  topLeft,

  /// Bottom-right corner.
  ///
  /// 右下角。
  bottomRight,

  /// Bottom-left corner.
  ///
  /// 左下角。
  bottomLeft,
}

/// Style configuration for the fullscreen native ad overlay.
///
/// Controls the appearance of the Flutter overlay wrapped around the platform
/// native ad view: background color, close button widget, top label, and
/// animation settings. Passed globally via [FlutterAdPlugin.init] and forwarded
/// to every fullscreen native ad presentation.
///
/// ## Usage
/// ```dart
/// FlutterAdPlugin.init(
///   fullScreenNativeStyle: AdFullScreenNativeStyle(
///     backgroundColor: Color(0xFF1A1A2E),
///     closeButtonPosition: AdCloseButtonPosition.topLeft,
///     closeButtonMargin: EdgeInsets.only(top: 50, left: 18),
///     closeButtonBuilder: (onClose) => GestureDetector(
///       onTap: onClose,
///       child: Container(
///         width: 40, height: 40,
///         decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
///         child: Icon(Icons.close, color: Colors.white, size: 24),
///       ),
///     ),
///   ),
/// );
/// ```
///
/// ---
/// 全屏原生广告遮罩层样式配置。
///
/// 控制全屏原生广告 Flutter 遮罩层的外观：背景色、关闭按钮 Widget、
/// 顶部标签和动画参数。通过 [FlutterAdPlugin.init] 全局传入，每次展示
/// 全屏原生广告时透传使用。
class AdFullScreenNativeStyle {
  /// Overlay background color.
  /// Defaults to `Colors.black`.
  ///
  /// 遮罩层背景色。默认 `Colors.black`。
  final Color backgroundColor;

  /// Dialog barrier color behind the overlay.
  /// Defaults to `Colors.black`.
  ///
  /// 对话框遮罩色。默认 `Colors.black`。
  final Color barrierColor;

  /// Transition animation duration for showing/dismissing the dialog.
  /// Defaults to 140ms.
  ///
  /// 对话框展示/关闭的转场动画时长。默认 140ms。
  final Duration transitionDuration;

  /// Top label widget displayed above the native ad content.
  /// - `null` (default): shows "Advertisement" with white text on transparent background.
  /// - `SizedBox.shrink()`: hides the label entirely.
  /// - Any custom widget: replaces the default label.
  ///
  /// 顶部标签 Widget。`null`=默认 "Advertisement" 白字标签；
  /// `SizedBox.shrink()`=隐藏；自定义 Widget=完全替换。
  final Widget? topLabel;

  /// Builder for the close button widget.
  ///
  /// Receives a [VoidCallback] (`onClose`) that must be called to dismiss the ad.
  /// Return `null` or omit this parameter to use the default yellow rounded
  /// close icon (`Icons.cancel_rounded`, `Color(0xFFFDF652)`, size 36).
  ///
  /// ## Example
  /// ```dart
  /// closeButtonBuilder: (onClose) => IconButton(
  ///   onPressed: onClose,
  ///   icon: Icon(Icons.close, color: Colors.white, size: 32),
  /// ),
  /// ```
  ///
  /// 关闭按钮 Widget 构建器。入参 `onClose` 须在点击时调用以关闭广告。
  /// 不传则使用默认黄色圆角关闭图标。
  final Widget Function(VoidCallback onClose)? closeButtonBuilder;

  /// Which corner the close button is anchored to.
  /// Defaults to [AdCloseButtonPosition.topRight].
  ///
  /// 关闭按钮锚定的角位。默认右上角。
  final AdCloseButtonPosition closeButtonPosition;

  /// Margin from the chosen corner's edges.
  ///
  /// For [AdCloseButtonPosition.topRight], uses `top` and `right` from this value.
  /// For [topLeft]: uses `top` and `left`.
  /// For [bottomRight]: uses `bottom` and `right`.
  /// For [bottomLeft]: uses `bottom` and `left`.
  ///
  /// When `null` (default), the margin is calculated as percentage of screen
  /// size for the selected corner: vertical = `max(56, height * 0.06)`,
  /// horizontal = `max(20, width * 0.06)`.
  ///
  /// 关闭按钮与所选角位的边距。`null` 时按屏幕百分比计算默认值。
  /// 根据 [closeButtonPosition] 决定取用 top/bottom/left/right 中的哪些值。
  final EdgeInsets? closeButtonMargin;

  /// Creates a [AdFullScreenNativeStyle] with the given configuration.
  ///
  /// All parameters are optional and default to match the original built-in
  /// style (black background, yellow close button at top-right corner).
  ///
  /// 所有参数可选，默认值匹配内置样式（黑色背景 + 右上角黄色关闭按钮）。
  const AdFullScreenNativeStyle({
    this.backgroundColor = const Color(0xFF000000),
    this.barrierColor = const Color(0xFF000000),
    this.transitionDuration = const Duration(milliseconds: 140),
    this.topLabel,
    this.closeButtonBuilder,
    this.closeButtonPosition = AdCloseButtonPosition.topRight,
    this.closeButtonMargin,
  });
}

/// Runtime model for ad configuration, produced by [AdConfigParser] from JSON.
///
/// All ad behavior (timeouts, cooldowns, cache sizes, policies) is driven by
/// this configuration object. The host app provides it through [AdConfigRepository].
///
/// ---
/// 广告配置的运行时模型，由 [AdConfigParser] 从 JSON 解析生成。
///
/// 所有广告行为（超时、CD、缓存数量、策略）均由本配置驱动。
/// 宿主通过 [AdConfigRepository] 提供此配置。
class AdConfig {
  /// Default load timeout in seconds for each ad unit (JSON key: `load_timeout`).
  /// Individual units can override this via [AdUnitConfig.loadTimeoutSeconds].
  ///
  /// 单个广告单元加载超时（秒）。JSON key: `load_timeout`。
  /// 单条广告单元可通过 [AdUnitConfig.loadTimeoutSeconds] 覆盖。
  final int loadTimeoutSeconds;

  /// Cooldown in seconds between two shows of the same placement
  /// (JSON key: `same_placement_cd`). Only enforced when the placement's
  /// [PlacementPolicy.applySamePlacementCd] is `true`.
  ///
  /// 同一广告位两次展示之间的冷却时间（秒）。JSON key: `same_placement_cd`。
  /// 仅在对应 [PlacementPolicy.applySamePlacementCd] 为 `true` 时生效。
  final int samePlacementCdSeconds;

  /// Cooldown in seconds between shows of different placements
  /// (JSON key: `different_placement_cd`). Only enforced when the placement's
  /// [PlacementPolicy.applyDifferentPlacementCd] is `true`.
  ///
  /// 不同广告位展示之间的全局冷却时间（秒）。JSON key: `different_placement_cd`。
  /// 仅在对应 [PlacementPolicy.applyDifferentPlacementCd] 为 `true` 时生效。
  final int differentPlacementCdSeconds;

  /// Fallback placements used when a requested placement is not configured
  /// (JSON key: `common_placements`). The engine iterates this list in order
  /// and uses the first available placement.
  ///
  /// 兜底广告位列表（JSON key: `common_placements`）。当请求的广告位未配置时，
  /// 引擎按顺序查找第一个已配置的兜底位。
  final List<PlacementType> commonPlacements;

  /// Optional high-value placement for prioritized ad display
  /// (JSON key: `high_value_placement`). When a placement's
  /// [PlacementPolicy.preferHighValueOnShow] is `true`, cached ads from this
  /// placement are preferred for display.
  ///
  /// 高价位广告位（JSON key: `high_value_placement`）。当对应广告位的
  /// [PlacementPolicy.preferHighValueOnShow] 为 `true` 时，优先展示此广告位的缓存广告。
  final PlacementType? highValuePlacement;

  /// The complete mapping from [PlacementType] to its configured ad units.
  /// Each placement is a key in the top-level JSON object (except reserved keys).
  ///
  /// 广告位到广告单元列表的完整映射。每个 placement 对应 JSON 中的一个顶层 key。
  final Map<PlacementType, List<AdUnitConfig>> placements;

  /// Per-placement display policies injected by the host via [FlutterAdPlugin.init].
  /// Policies not provided here fall back to [PlacementPolicy.defaultPolicy].
  ///
  /// 宿主通过 [FlutterAdPlugin.init] 注入的各广告位展示策略。
  /// 未提供的 placement 使用 [PlacementPolicy.defaultPolicy]。
  final Map<PlacementType, PlacementPolicy> policies;

  const AdConfig({
    required this.loadTimeoutSeconds,
    required this.samePlacementCdSeconds,
    required this.differentPlacementCdSeconds,
    this.commonPlacements = const [],
    this.highValuePlacement,
    required this.placements,
    this.policies = const {},
  });

  /// Returns the units configured for [placement], or an empty list.
  ///
  /// 返回指定广告位的广告单元列表，未配置时返回空列表。
  List<AdUnitConfig> getUnits(PlacementType placement) {
    return placements[placement] ?? const [];
  }

  /// Total cache pool size for [placement] across all ad unit types.
  /// Always at least [minimum].
  ///
  /// 广告位缓存池总大小，取所有配置单元的 poolSize 最大值。至少为 [minimum]。
  int cacheSizeFor(PlacementType placement, {int minimum = 1}) {
    var size = minimum;
    for (final unit in getUnits(placement)) {
      if (unit.poolSize > size) {
        size = unit.poolSize;
      }
    }
    return size;
  }

  /// Cache pool size for fullscreen ad types only (open/interstitial/rewarded).
  ///
  /// 全屏类型（open/interstitial/rewarded）的缓存池大小。
  int fullscreenCacheSizeFor(PlacementType placement, {int minimum = 1}) {
    return _cacheSizeFor(
      placement,
      minimum: minimum,
      include: (unit) => unit.type.isFullscreen,
    );
  }

  /// Cache pool size for native ad types only (native/double_native).
  ///
  /// 原生类型（native/double_native）的缓存池大小。
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

  /// Effective load timeout for [unit]. Falls back to global [loadTimeoutSeconds].
  ///
  /// 广告单元的实际加载超时，未覆盖则使用全局 [loadTimeoutSeconds]。
  Duration loadTimeoutFor(AdUnitConfig unit) {
    return Duration(seconds: unit.loadTimeoutSeconds ?? loadTimeoutSeconds);
  }

  /// Display policy for [placement], or a default if not explicitly set.
  ///
  /// 展示策略，未显式设置则使用默认策略。
  PlacementPolicy getPolicy(PlacementType placement) {
    return policies[placement] ??
        PlacementPolicy.defaultPolicy(this, placement);
  }

  /// All placements with at least one configured ad unit.
  ///
  /// 所有已配置至少一个广告单元的 placement。
  Iterable<PlacementType> get configuredPlacements => placements.keys;

  /// Whether [placement] has at least one valid ad unit.
  ///
  /// 指定广告位是否有至少一个有效广告单元。
  bool hasPlacement(PlacementType placement) {
    return getUnits(placement).isNotEmpty;
  }
}

/// Configuration for a single ad unit within a placement.
///
/// Each ad unit corresponds to one ad slot that can be loaded and shown.
/// When a placement has multiple IDs (via `id`/`id2`/`ids`), each ID produces
/// a separate [AdUnitConfig] with its own [cacheKey] for deduplication.
///
/// ---
/// 单个广告单元的配置模型。
///
/// 每个广告单元对应一个可加载和展示的广告槽位。当一个 placement
/// 配置了多个 ID 时，每个 ID 都生成独立的 [AdUnitConfig]。
class AdUnitConfig {
  /// The ad network this unit belongs to (JSON key: `source` / `ad_source`).
  ///
  /// 广告来源平台（JSON key: `source` / `ad_source`）。
  final AdSource source;

  /// Priority weight: higher values are tried first during preloading and
  /// show-slot selection (JSON key: `weight` / `ad_weight`).
  ///
  /// 优先级权重：预加载和展示选槽时优先尝试高权重单元
  /// （JSON key: `weight` / `ad_weight`）。
  final int weight;

  /// Ad format: `open`, `interstitial`, `rewarded`, `native`, or `double_native`
  /// (JSON key: `type` / `ad_type`).
  ///
  /// 广告形式（JSON key: `type` / `ad_type`）。
  final AdType type;

  /// AdMob (or other network) ad unit ID for this slot
  /// (JSON key: `id` / `ad_id`).
  ///
  /// 广告单元 ID（JSON key: `id` / `ad_id`）。
  final String id;

  /// Unique key used for deduplication in the ad cache pool.
  /// Generated as `{source}_{type}_{index}_{id}` by the parser.
  ///
  /// 缓存去重键，由解析器生成为 `{source}_{type}_{index}_{id}`。
  final String cacheKey;

  /// AdMob native template style: `"small"` or `"medium"`
  /// (JSON key: `template_type`). Only applicable when `factoryId` is `null`
  /// for inline native ads.
  ///
  /// AdMob 原生模板尺寸（JSON key: `template_type`）。仅在内联原生且
  /// 未指定自定义 factory 时生效。
  final String? templateType;

  /// Auto-refresh interval in minutes for native ads
  /// (JSON key: `refresh_minutes`). The cached ad is discarded and reloaded
  /// after this interval.
  ///
  /// 原生广告缓存自动刷新间隔分钟数（JSON key: `refresh_minutes`）。
  final int? refreshMinutes;

  /// Per-unit load timeout override in seconds (JSON key: `load_timeout`).
  /// Falls back to [AdConfig.loadTimeoutSeconds] when not set.
  ///
  /// 此广告单元的加载超时秒数（JSON key: `load_timeout`）。
  /// 未设置时使用 [AdConfig.loadTimeoutSeconds]。
  final int? loadTimeoutSeconds;

  /// Number of ad slots to cache for this unit. Derived from the number of
  /// IDs provided (id, id2, ids, idN) for the same row in JSON.
  ///
  /// 此单元需缓存的广告槽数，由 JSON 中 ID 展开的数量决定。
  final int poolSize;

  /// Custom native ad factory ID for this ad unit.
  ///
  /// When set, the adapter uses this factory ID instead of the deprecated
  /// [AdmobNativeAdapter.fullScreenFactoryId] or AdMob's built-in
  /// `NativeTemplateStyle`. The host app must register a matching
  /// `NativeAdFactory` on the native side (Android `MainActivity` /
  /// iOS `AppDelegate`) under this ID.
  ///
  /// Configure via JSON key `native_factory_id`:
  /// ```json
  /// { "source": "admob", "type": "native",
  ///   "id": "ca-app-pub-xxx", "native_factory_id": "my_custom_factory" }
  /// ```
  ///
  /// 自定义原生广告工厂 ID。设置后将替代已弃用的 `fullScreenFactoryId`
  /// 或 AdMob 内置模板。宿主需在 Android/iOS 原生侧注册同名 `NativeAdFactory`。
  final String? nativeFactoryId;

  /// Banner ad size preset (JSON key: `banner_size`).
  ///
  /// Supported values: `"banner"` (320x50, default), `"large_banner"` (320x100),
  /// `"medium_rectangle"` (300x250), `"leaderboard"` (728x90).
  /// Only applicable when [type] is [AdType.banner].
  ///
  /// Banner 广告尺寸预设（JSON key: `banner_size`）。
  /// 可选值：`banner` / `large_banner` / `medium_rectangle` / `leaderboard`。
  /// 仅在 [type] 为 [AdType.banner] 时生效。
  final String? bannerSize;

  /// Banner lifecycle mode (JSON key: `banner_mode`).
  ///
  /// - `"global"` (default): auto-preloaded by `preloadPlacements()`, auto-refreshed
  ///   per `refresh_minutes`. Persists across page navigation. Retrieve with
  ///   `getBannerAd()` at any time.
  /// - `"inline"`: manually controlled via `loadBanner()` / `disposeBannerAd()`.
  ///   NOT auto-preloaded. Dispose explicitly when the page/widget is removed.
  ///
  /// Banner 生命周期模式（JSON key: `banner_mode`）。
  /// - `global`（默认）：由 preloadPlacements 自动预加载，按 refresh_minutes 自动刷新，
  ///   跨页面持久。随时通过 getBannerAd 取用。
  /// - `inline`：手动调用 loadBanner / disposeBannerAd 控制。不自动预加载，
  ///   页面退出时需主动销毁。
  final String? bannerMode;

  /// Whether this banner unit is in global (persistent) mode.
  ///
  /// 是否是全局持久模式。
  bool get isGlobalBanner => bannerMode?.trim().toLowerCase() != 'inline';

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
    this.nativeFactoryId,
    this.bannerSize,
    this.bannerMode,
  }) : cacheKey = cacheKey ?? id;

  bool get isValid => id.isNotEmpty;
}

/// Display policy for a single placement.
///
/// Injected by the host through [FlutterAdPlugin.init] `placementPolicies`.
/// Policies not provided fall back to [PlacementPolicy.defaultPolicy].
///
/// ---
/// 单个广告位的展示策略。由宿主通过 [FlutterAdPlugin.init]
/// `placementPolicies` 注入。未配置时使用默认策略。
class PlacementPolicy {
  /// Whether this placement enters the fullscreen show path.
  /// When `true`, native ad units in this placement are rendered as
  /// fullscreen native ads. Auto-inferred from the presence of fullscreen
  /// ad-unit types if not explicitly set.
  ///
  /// 是否走全屏展示链路。`true` 时原生广告单元以全屏形式展示。
  /// 未显式设置时根据广告单元类型自动推导。
  final bool isFullscreen;

  /// Whether same-placement cooldown is enforced for this placement.
  ///
  /// 是否启用同广告位冷却。
  final bool applySamePlacementCd;

  /// Whether cross-placement (global) cooldown is enforced for this placement.
  ///
  /// 是否启用跨广告位全局冷却。
  final bool applyDifferentPlacementCd;

  /// Whether showing this placement marks the global cooldown timestamp.
  /// Controls whether THIS placement's display blocks OTHER placements.
  ///
  /// 展示本广告位后是否写入全局冷却时间戳，影响其他广告位。
  final bool contributesToGlobalCooldown;

  /// Whether `onAdNotReady` is triggered when no ad is cached and
  /// [waitForLoadOnShow] is disabled.
  ///
  /// 无广告可展示时是否触发 `onAdNotReady` 回调。
  final bool showNotReadyToast;

  /// Whether [FlutterAdPlugin.show] triggers a preload when the cache is empty.
  /// Recommended `true` for most placements, `false` for `open` (cold start).
  ///
  /// [show()] 无缓存时是否等待加载。建议大多数 placement 设为 `true`，
  /// 冷启动开屏 `open` 设为 `false`。
  final bool waitForLoadOnShow;

  /// Whether to prefer ads from the high-value placement over this placement's
  /// own cache. Recommended `true` for interstitial placements, `false` for
  /// `open` (critical to show something immediately).
  ///
  /// 是否优先使用高价位广告位缓存。
  final bool preferHighValueOnShow;

  /// Custom message for the `onAdNotReady` callback. When `null`, the engine
  /// uses a default English message.
  ///
  /// `onAdNotReady` 的自定义提示语。`null` 时使用默认英文文案。
  final String? notReadyMsg;

  /// Allowlist of [AdType] values this placement accepts.
  /// When `null`, all types allowed by the isFullscreen derivation are accepted.
  ///
  /// 允许的广告类型白名单。`null` 时按 isFullscreen 推导规则放行。
  final Set<AdType>? allowedTypes;

  const PlacementPolicy({
    required this.isFullscreen,
    required this.applySamePlacementCd,
    required this.applyDifferentPlacementCd,
    required this.contributesToGlobalCooldown,
    required this.showNotReadyToast,
    required this.waitForLoadOnShow,
    required this.preferHighValueOnShow,
    this.notReadyMsg,
    this.allowedTypes,
  });

  /// Creates a sensible default policy based on the placement configuration.
  ///
  /// - `isFullscreen` is `true` if any unit in the placement is a fullscreen type.
  /// - `waitForLoadOnShow` and `preferHighValueOnShow` are `false` for `open`
  ///   (cold start must return immediately), `true` for all others.
  /// - All other flags default to `false`.
  ///
  /// 根据广告位配置推导默认策略：
  /// - 含全屏类广告单元时 `isFullscreen=true`
  /// - `open` 广告位的 waitForLoadOnShow / preferHighValueOnShow 为 `false`
  /// - 其余标记默认 `false`
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
      waitForLoadOnShow: placement.name != 'open',
      preferHighValueOnShow: placement.name != 'open',
    );
  }

  /// Whether [type] is allowed to be shown in this placement.
  /// When [allowedTypes] is set, only those types pass.
  /// Otherwise, fullscreen placements accept fullscreen + native types;
  /// non-fullscreen placements accept native and banner types.
  ///
  /// 指定广告类型是否可在此 placement 中展示。
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

/// Parses a JSON Map into an [AdConfig] runtime model.
///
/// Top-level keys that are arrays of ad-unit objects are treated as placements.
/// Reserved keys (`load_timeout`, `same_placement_cd`, etc.) are parsed as
/// global settings.
///
/// ---
/// 将 JSON Map 解析为 [AdConfig] 运行时模型。
/// 顶层 key 为广告单元列表时识别为 placement；保留 key 解析为全局配置。
class AdConfigParser {
  /// Parses [json] into an [AdConfig].
  ///
  /// 将 [json] 解析为 [AdConfig]。
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
      samePlacementCdSeconds:
          (json['same_placement_cd'] as num?)?.toInt() ?? 30,
      differentPlacementCdSeconds:
          (json['different_placement_cd'] as num?)?.toInt() ?? 30,
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
        refreshMinutes: (json['refresh_minutes'] as num?)?.toInt(),
        loadTimeoutSeconds: (json['load_timeout'] as num?)?.toInt(),
        poolSize: ids.length,
        nativeFactoryId: json['native_factory_id'] as String?,
        bannerSize: json['banner_size'] as String?,
        bannerMode: json['banner_mode'] as String?,
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

/// Interface for fetching ad configuration.
///
/// The host app provides an implementation (remote config, local JSON,
/// Firebase Remote Config, etc.). The plugin calls [getConfig] during
/// initialization and before each ad operation.
///
/// 广告配置仓库接口。宿主实现后可接远端配置、本地 JSON、Firebase Remote Config 等。
/// 插件在初始化和每次广告操作时调用 [getConfig]。
abstract class AdConfigRepository {
  /// Returns the current [AdConfig]. Must be safe to call multiple times;
  /// implementations should cache the result if fetching is expensive.
  ///
  /// 返回当前 [AdConfig]。支持多次调用，建议实现方缓存结果。
  Future<AdConfig> getConfig();
}

/// Default [AdConfigRepository] that parses a local Map or JSON string.
///
/// Suitable for demos and simple use cases. Production apps should typically
/// implement their own repository backed by remote config or A/B testing.
///
/// ---
/// 默认配置仓库，解析本地 Map 或 JSON 字符串。适用于 Demo 和简单场景。
/// 正式项目建议接入远端配置或 A/B 实验后自行实现。
class DefaultAdConfigRepository implements AdConfigRepository {
  /// Creates a repository from [localConfig] (a Dart Map) and/or
  /// [localConfigJson] (a JSON string). When both are provided,
  /// [localConfigJson] takes priority.
  ///
  /// [placementPolicies] are merged into the parsed [AdConfig].
  ///
  /// [localConfig] 和 [localConfigJson] 同时提供时以后者为准。
  /// [placementPolicies] 会合并入解析后的 [AdConfig]。
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
      samePlacementCdSeconds: config.samePlacementCdSeconds,
      differentPlacementCdSeconds: config.differentPlacementCdSeconds,
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
