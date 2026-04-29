import 'ad_enums.dart';
import 'ad_config.dart';

class PlacementPolicy {
  final bool isFullscreen;
  final bool applySamePlacementCd;
  final bool applyDifferentPlacementCd;
  final bool contributesToGlobalCooldown;
  final bool showNotReadyToast;

  const PlacementPolicy({
    required this.isFullscreen,
    required this.applySamePlacementCd,
    required this.applyDifferentPlacementCd,
    required this.contributesToGlobalCooldown,
    required this.showNotReadyToast,
  });
}

class PlacementPolicies {
  static PlacementPolicy of({
    required AdConfig config,
    required PlacementType placement,
  }) {
    final custom = config.getPolicy(placement);
    final units = config.getUnits(placement);
    final hasNative = units.any((u) => u.type == AdType.native);
    final isFullscreenByType = !hasNative;

    return PlacementPolicy(
      isFullscreen: custom?.isFullscreen ?? isFullscreenByType,
      applySamePlacementCd: custom?.applySamePlacementCd ?? isFullscreenByType,
      applyDifferentPlacementCd:
          custom?.applyDifferentPlacementCd ?? isFullscreenByType,
      contributesToGlobalCooldown:
          custom?.contributesToGlobalCooldown ?? isFullscreenByType,
      showNotReadyToast: custom?.showNotReadyToast ?? isFullscreenByType,
    );
  }
}
