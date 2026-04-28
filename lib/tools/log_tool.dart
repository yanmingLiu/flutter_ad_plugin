import 'package:flutter/foundation.dart';

final log = AppLogger();

class AppLogger {
  void d(Object message) {
    debugPrint(message.toString());
  }

  void e(Object message) {
    debugPrint('[error] $message');
  }
}
