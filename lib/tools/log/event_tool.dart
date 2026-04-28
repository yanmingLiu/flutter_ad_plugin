import 'package:flutter/foundation.dart';

Future<void> logEvent(
  String name, {
  Map<String, Object?> parameters = const {},
}) async {
  debugPrint('[analytics] $name $parameters');
}

Future<void> logAdEvent({
  required String adid,
  required String placement,
  required String adType,
  required String adSource,
  required String adNetwork,
  double? value,
  String? currency,
}) async {
  debugPrint(
    '[analytics][ad_income] adid=$adid placement=$placement '
    'type=$adType source=$adSource network=$adNetwork value=$value currency=$currency',
  );
}

class SvrLogEvent {
  void logSessionEvent() {
    debugPrint('[analytics] session_foreground');
  }
}
