import 'package:flutter/widgets.dart';

import '../../tools/log_tool.dart';
import '../core/ad_enums.dart';
import 'ad_service.dart';

class AdLifecycleService with WidgetsBindingObserver {
  AdLifecycleService(this._adService);

  final AdService _adService;
  bool _isHandlingForeground = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onForeground();
    }
  }

  Future<void> _onForeground() async {
    if (_isHandlingForeground) return;
    _isHandlingForeground = true;
    try {
      await _adService.show(PlacementType.open);
    } catch (e) {
      log.e('[ad] lifecycle foreground show failed: $e');
    } finally {
      _isHandlingForeground = false;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
