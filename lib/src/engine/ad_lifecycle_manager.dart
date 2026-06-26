import 'dart:async';

import 'package:flutter/foundation.dart';

/// Manages all ad refresh timers in one place.
///
/// Replaces the scattered `Timer` instances in the old [AdEngine].
/// Provides guaranteed cleanup via [dispose].
///
/// ---
/// 统一管理所有广告刷新定时器，替代旧 AdEngine 中散落的 Timer。
/// 通过 dispose 保证清理。
class AdLifecycleManager {
  final Map<String, Timer> _timers = {};

  /// Schedules a refresh callback after [minutes] (default 40).
  /// If a timer already exists for [key], cancels it first.
  void scheduleRefresh(
    String key,
    int? minutes,
    VoidCallback onRefresh,
  ) {
    _timers.remove(key)?.cancel();
    _timers[key] = Timer(
      Duration(minutes: minutes ?? 40),
      () {
        _timers.remove(key);
        onRefresh();
      },
    );
  }

  /// Cancels a specific refresh timer.
  void cancelRefresh(String key) {
    _timers.remove(key)?.cancel();
  }

  /// Whether a timer is active for [key].
  bool hasRefresh(String key) => _timers.containsKey(key);

  /// Cancels all timers. Call on [AdPlugin.dispose].
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
