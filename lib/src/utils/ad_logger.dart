import 'package:flutter/foundation.dart';

import 'ad_reporter.dart';

final log = AppLogger();

class AppLogger {
  bool verboseEnabled = true;

  void d(Object message) {
    debugPrint('[ad] $message');
  }

  void event(AdEvent event) {
    final type = event.eventType;
    final placement = (event.placement?.name ?? '-').padRight(14);
    final adType = (event.adType?.name ?? '-').padRight(13);
    final adId = _formatAdUnitId(event.adUnitId).padRight(12);
    final eventName = (event.eventName ?? '-').padRight(14);

    if (!verboseEnabled && !(type?._printsByDefault ?? false)) {
      return;
    }

    final label = type == null ? 'EVENT' : _labelFor(type);
    final extra = _extraFields(event);

    debugPrint('[ad] $label $placement $adType $adId $eventName$extra');
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

String _labelFor(AdEventType type) {
  switch (type) {
    case AdEventType.loadRequested:
      return 'REQ  ';
    case AdEventType.loadSucceeded:
      return 'OK   ';
    case AdEventType.loadFailed:
      return 'ERR  ';
    case AdEventType.show:
      return 'SHOW ';
    case AdEventType.showSuccess:
      return 'DONE ';
    case AdEventType.showFail:
      return 'FAIL ';
    case AdEventType.clicked:
      return 'CLICK';
    case AdEventType.income:
      return 'PAID ';
    case AdEventType.close:
      return 'CLOSE';
  }
}

String _extraFields(AdEvent event) {
  final buf = StringBuffer();
  final r = event.revenue;
  if (r != null) {
    final currency = event.currency ?? '';
    buf.write(' revenue=$r $currency');
  }
  final err = event.errorReason;
  if (err != null && err.isNotEmpty) {
    buf.write(' error=$err');
  }
  final net = event.network;
  if (net != null && net.isNotEmpty) {
    buf.write(' network=$net');
  }
  final requested = event.requestedPlacement;
  if (requested != null && requested != event.placement) {
    buf.write(' request=${requested.name}');
  }
  return buf.toString();
}

String _formatAdUnitId(String? adUnitId) {
  if (adUnitId == null || adUnitId.isEmpty) {
    return '-';
  }
  final idx = adUnitId.lastIndexOf('/');
  if (idx >= 0 && idx < adUnitId.length - 1) {
    return '...${adUnitId.substring(idx + 1)}';
  }
  if (adUnitId.length > 12) {
    return '...${adUnitId.substring(adUnitId.length - 8)}';
  }
  return adUnitId;
}
