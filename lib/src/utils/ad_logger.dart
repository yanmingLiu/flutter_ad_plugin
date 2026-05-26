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
    if (verboseEnabled || event.eventType._printsByDefault) {
      debugPrint('[ad][event] ${jsonEncode(event.toJson())}');
    }
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

extension on AdEventType {
  bool get _printsByDefault {
    return this == AdEventType.loadFailed || this == AdEventType.showFail;
  }
}
