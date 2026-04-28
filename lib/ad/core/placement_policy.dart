import 'ad_enums.dart';

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
  static const Map<PlacementType, PlacementPolicy> values = {
    PlacementType.open: PlacementPolicy(
      isFullscreen: true,
      applySamePlacementCd: true,
      applyDifferentPlacementCd: true,
      contributesToGlobalCooldown: true,
      showNotReadyToast: false,
    ),
    PlacementType.home: PlacementPolicy(
      isFullscreen: false,
      applySamePlacementCd: false,
      applyDifferentPlacementCd: false,
      contributesToGlobalCooldown: false,
      showNotReadyToast: false,
    ),
    PlacementType.message: PlacementPolicy(
      isFullscreen: true,
      applySamePlacementCd: false,
      applyDifferentPlacementCd: false,
      contributesToGlobalCooldown: false,
      showNotReadyToast: true,
    ),
    PlacementType.chatBack: PlacementPolicy(
      isFullscreen: true,
      applySamePlacementCd: true,
      applyDifferentPlacementCd: true,
      contributesToGlobalCooldown: true,
      showNotReadyToast: false,
    ),
    PlacementType.chatSession: PlacementPolicy(
      isFullscreen: true,
      applySamePlacementCd: true,
      applyDifferentPlacementCd: true,
      contributesToGlobalCooldown: true,
      showNotReadyToast: false,
    ),
    PlacementType.liveVideo: PlacementPolicy(
      isFullscreen: true,
      applySamePlacementCd: false,
      applyDifferentPlacementCd: false,
      contributesToGlobalCooldown: false,
      showNotReadyToast: true,
    ),
  };

  static PlacementPolicy of(PlacementType placement) => values[placement]!;
}
