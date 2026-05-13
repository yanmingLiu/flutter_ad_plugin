import 'package:flutter/widgets.dart';

import '../utils/ad_logger.dart';
import '../core/ad_enums.dart';
import 'ad_engine.dart';

class AdLifecycle with WidgetsBindingObserver {
  AdLifecycle(this._engine);

  final AdEngine _engine;
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
      await _engine.show(PlacementType.open);
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
