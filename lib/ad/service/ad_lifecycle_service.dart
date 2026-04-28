import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../tools/log/event_tool.dart';
import '../../tools/log_tool.dart';
import '../core/ad_enums.dart';
import 'ad_service.dart';

class AdLifecycleService {
  AdLifecycleService(this._adService);

  final AdService _adService;
  bool _isHandlingForeground = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    AppStateEventNotifier.startListening();
    AppStateEventNotifier.appStateStream.listen((state) async {
      if (state == AppState.foreground) {
        await _onForeground();
      }
    });
  }

  Future<void> _onForeground() async {
    if (_isHandlingForeground) return;
    _isHandlingForeground = true;
    try {
      SvrLogEvent().logSessionEvent();

      await _adService.show(PlacementType.open);
    } catch (e) {
      log.e('[ad] lifecycle foreground show failed: $e');
    } finally {
      _isHandlingForeground = false;
    }
  }
}
