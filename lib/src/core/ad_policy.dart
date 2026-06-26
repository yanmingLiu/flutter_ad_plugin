import 'ad_config.dart';
import 'ad_enums.dart';

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
  final bool isFullscreen;

  /// Whether same-placement cooldown is enforced.
  final bool applySamePlacementCd;

  /// Whether cross-placement (global) cooldown is enforced.
  final bool applyDifferentPlacementCd;

  /// Whether showing this placement marks the global cooldown timestamp.
  final bool contributesToGlobalCooldown;

  /// Whether `onAdNotReady` is triggered when no ad is cached.
  final bool showNotReadyToast;

  /// Whether [show] triggers a preload when the cache is empty.
  final bool waitForLoadOnShow;

  /// Whether to prefer ads from the high-value placement.
  final bool preferHighValueOnShow;

  /// Custom message for `onAdNotReady` callback.
  final String? notReadyMsg;

  /// Allowlist of [AdType] values this placement accepts.
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
