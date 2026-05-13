import 'dart:async';

import '../../tools/log_tool.dart';
import '../core/ad_enums.dart';
import 'ad_service.dart';

class AdPreloadService {
  const AdPreloadService(this.adService);

  final AdService adService;

  Future<bool> preloadStartupAds() async {
    log.d('📥 [startup] preloading: open');
    final openReady = await adService.preload(PlacementType.open);
    log.d('📥 [startup] finish: open (ready=$openReady)');

    return openReady;
  }

  Future<void> preloadSecondaryAds() async {
    try {
      log.d('📥 [startup] secondary_start');
      await Future.wait([
        adService.preload(PlacementType.message),
        adService.preload(PlacementType.chatBack),
        adService.preload(PlacementType.chatSession),
        adService.preload(PlacementType.liveVideo),
      ]);
      log.d('📥 [startup] secondary_finish');
    } catch (_) {}
  }
}
