import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ad_reporter.dart';

final log = AppLogger();

class AppLogger {
  bool verboseEnabled = false;

  void d(Object message) {
    debugPrint('[ad] $message');
  }

  void event(AdEvent event) {
    debugPrint('[ad][event] ${jsonEncode(event.toJson())}');
  }

  void v(Object message) {
    if (verboseEnabled) {
      debugPrint('[ad] $message');
    }
  }

  void e(Object message) {
    debugPrint('[ad] $message');
  }
}
