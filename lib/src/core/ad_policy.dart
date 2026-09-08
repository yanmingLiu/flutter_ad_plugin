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
