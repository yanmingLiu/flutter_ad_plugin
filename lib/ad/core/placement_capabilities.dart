import 'ad_enums.dart';
import 'ad_config.dart';

class PlacementCapabilities {
  static bool supports({
    required AdConfig config,
    required PlacementType placement,
    required AdType type,
  }) {
    final units = config.getUnits(placement);
    if (units.isEmpty) return false;
    return units.any((u) => u.type == type);
  }
}
