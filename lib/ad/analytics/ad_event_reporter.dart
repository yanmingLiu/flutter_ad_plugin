import '../../tools/log/event_tool.dart';
import '../../tools/log_tool.dart';
import '../core/ad_enums.dart';
import 'ad_event.dart';

abstract class AdEventReporter {
  Future<void> report(AdEvent event);
}

class DefaultAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    final placementValue = event.placementLabel ?? event.placement;
    log.d(
      '[ad] 👉 ${event.eventType.name} placement=$placementValue '
      'type=${event.adType.name} unit=${event.adUnitId}',
    );

    switch (event.eventType) {
      case AdEventType.loadRequested:
        logEvent(
          'adreq',
          parameters: {'value': placementValue, 'adid': event.adUnitId},
        );
        break;
      case AdEventType.loadSucceeded:
        logEvent(
          'adreq_succ',
          parameters: {'value': placementValue, 'adid': event.adUnitId},
        );
        break;
      case AdEventType.loadFailed:
        logEvent(
          'adreq_fail',
          parameters: {
            'value': placementValue,
            'adid': event.adUnitId,
            'code': '${event.errorCode ?? -1}',
            'reason': event.errorReason ?? '',
            'type': event.adType.name,
          },
        );
        break;
      case AdEventType.show:
        logEvent(
          'ad_show',
          parameters: {'value': placementValue, 'adid': event.adUnitId},
        );
        break;
      case AdEventType.showSuccess:
        logEvent(
          'ad_show_succ',
          parameters: {'value': placementValue, 'adid': event.adUnitId},
        );
        break;
      case AdEventType.showFail:
        logEvent(
          'ad_show_fail',
          parameters: {
            'value': placementValue,
            'adid': event.adUnitId,
            'code': '${event.errorCode ?? -1}',
            'reason': event.errorReason ?? '',
            'type': event.adType.name,
          },
        );
        break;
      case AdEventType.clicked:
        logEvent('ad_click');
        break;
      case AdEventType.income:
        logEvent(
          'ad_income',
          parameters: {
            'value': '${event.revenue ?? 0}',
            'currency': event.currency ?? '',
            'adid': event.adUnitId,
          },
        );
        logAdEvent(
          adid: event.adUnitId,
          placement: placementValue,
          adType: event.adType.name,
          adSource: event.source.name,
          adNetwork: event.source.name,
          value: event.revenue,
          currency: event.currency,
        );
        break;
      case AdEventType.rewardEarned:
        logEvent('ad_reward_$placementValue', parameters: {'parameters': '1'});
        break;
      case AdEventType.close:
        logEvent(
          'ad_colse',
          parameters: {'value': placementValue, 'adid': event.adUnitId},
        );
        break;
      case AdEventType.blockedByGuard:
        logEvent(
          'ad_blocked_by_guard',
          parameters: {'value': placementValue, 'adid': event.adUnitId},
        );
        break;
    }
  }
}
