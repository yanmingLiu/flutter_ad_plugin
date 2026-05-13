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
      final config = await adService.config;
      final preloadList = config.preloadList;
      if (preloadList.isEmpty) return;

      log.d('📥 [startup] secondary_start: ${preloadList.length} units');
      await Future.wait(preloadList.map((p) => adService.preload(p)));
      log.d('📥 [startup] secondary_finish');
    } catch (_) {}
  }
}
