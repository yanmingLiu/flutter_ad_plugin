import 'dart:async';

import '../../tools/log_tool.dart';
import '../core/ad_enums.dart';
import 'ad_service.dart';

class AdPreloadService {
  const AdPreloadService(this.adService);

  final AdService adService;

  Future<bool> preloadStartupAds() async {
    log.d('[ad][startup_preload] open_start');
    final openReady = await adService.preload(Placements.open);
    log.d('[ad][startup_preload] open_finish ready=$openReady');

    return openReady;
  }

  Future<void> preloadSecondaryAds() async {
    try {
      log.d('[ad][startup_preload] secondary_start');
      await Future.wait([
        adService.preload(Placements.message),
        adService.preload(Placements.chatBack),
        adService.preload(Placements.chatSession),
        adService.preload(Placements.liveVideo),
      ]);
      log.d('[ad][startup_preload] secondary_finish');
    } catch (_) {}
  }
}
