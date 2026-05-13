import 'ad_enums.dart';

class PlacementCapabilities {
  static const Map<PlacementType, Set<AdType>> allowed = {
    PlacementType.open: {
      AdType.open,
      AdType.interstitial,
      AdType.rewarded,
    },
    PlacementType.home: {
      AdType.native,
    },
    PlacementType.message: {
      AdType.interstitial,
      AdType.rewarded,
    },
    PlacementType.chatBack: {
      AdType.interstitial,
      AdType.rewarded,
    },
    PlacementType.chatSession: {
      AdType.interstitial,
      AdType.rewarded,
    },
    PlacementType.liveVideo: {
      AdType.interstitial,
      AdType.rewarded,
    },
  };

  static bool supports(PlacementType placement, AdType type) {
    return allowed[placement]?.contains(type) ?? false;
  }
}
