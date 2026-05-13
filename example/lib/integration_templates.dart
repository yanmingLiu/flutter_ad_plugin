import 'dart:convert';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'utils/facebook_util.dart';

class MyConfigRepository implements AdConfigRepository {
  static const Map<String, dynamic> _jsonConfig = {
    'load_timeout': 7,
    'same_placement_cd': 30,
    'different_placement_cd': 30,
    'preload_list': ['open', 'home', 'message'],
    'placement_policy': {
      'open': {
        'apply_same_placement_cd': true,
        'apply_different_placement_cd': true,
        'contributes_to_global_cooldown': true,
      },
      'message': {
        'show_not_ready_toast': true,
        'not_ready_msg': 'Ad is still loading, please wait a moment.',
      },
    },
    'open': [
      {
        'source': 'admob',
        'weight': 3,
        'type': 'open',
        'id': 'ca-app-pub-3940256099942544/5575463023',
      },
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
    ],
    'home': [
      {
        'source': 'admob',
        'weight': 1,
        'type': 'native',
        'id': 'ca-app-pub-3940256099942544/1044960115',
        'template_type': 'medium',
        'refresh_minutes': 20,
      },
    ],
    'message': [
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
    ],
  };

  static String get rawJson => jsonEncode(_jsonConfig);

  @override
  Future<AdConfig> getConfig() async {
    return AdConfigParser().parse(_jsonConfig);
  }
}

class MyAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    // ignore: avoid_print
    print(
      '[my-ad-event] type=${event.eventType.name} placement=${event.placement} unit=${event.adUnitId}',
    );

    // 示例：将广告收入上报至 Facebook
    if (event.eventType == AdEventType.income && event.revenue != null) {
      FacebookSDKUtil.logAdImpression(
        value: event.revenue!,
        currency: event.currency ?? 'USD',
        adType: event.adType.name,
        adSource: event.source.name,
        adUnitId: event.adUnitId,
      );
    }
  }
}
