import 'package:flutter/widgets.dart';

import '../utils/ad_logger.dart';
import '../core/ad_enums.dart';
import 'ad_engine.dart';

class AdLifecycle with WidgetsBindingObserver {
  AdLifecycle(this._engine);

  final AdEngine _engine;
  bool _isHandlingForeground = false;
  bool _started = false;
  DateTime? _startTime;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _startTime = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onForeground();
    }
  }

  Future<void> _onForeground() async {
    if (_isHandlingForeground) {
      return;
    }

    // 冷启动保护：如果启动不到 3 秒，不自动触发开屏，由业务侧（如 Splash）手动控制
    if (_startTime != null &&
        DateTime.now().difference(_startTime!).inSeconds < 3) {
      return;
    }

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
