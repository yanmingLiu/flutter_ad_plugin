import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

import 'utils/facebook_util.dart';

class MyConfigRepository extends DefaultAdConfigRepository {
  MyConfigRepository() : super(localConfig: localConfig);

  // dart format off
  static const Map<String, dynamic> localConfig = {
    "load_timeout": 7,
    "same_placement_cd": 30,
    "different_placement_cd": 30,
    "preload_list": [
        "open",
        "home",
        "message",
        "double_ad"
    ],
    "placement_policy": {
        "open": {
            "apply_same_placement_cd": true,
            "apply_different_placement_cd": true,
            "contributes_to_global_cooldown": true
        },
        "message": {
            "show_not_ready_toast": true,
            "not_ready_msg": "Ad is still loading, please wait a moment."
        },
        "double_ad": {
            "show_not_ready_toast": true,
            "not_ready_msg": "Ad is still loading, please wait a moment."
        }
    },
    "open": [
        {
            "source": "admob",
            "weight": 3,
            "type": "open",
            "id": "ca-app-pub-3940256099942544/5575463023",
            "id2": "ca-app-pub-3940256099942544/4411468910"
        },
        {
            "source": "admob",
            "weight": 2,
            "type": "interstitial",
            "id": "ca-app-pub-3940256099942544/4411468910"
        }
    ],
    "home": [
        {
            "source": "admob",
            "weight": 1,
            "type": "native",
            "id": "ca-app-pub-3940256099942544/3986624511",
            "id2": "ca-app-pub-3940256099942544/2521693316",
            "template_type": "medium",
            "refresh_minutes": 20
        }
    ],
    "message": [
        {
            "source": "admob",
            "weight": 2,
            "type": "interstitial",
            "id": "ca-app-pub-3940256099942544/4411468910",
            "load_timeout": 15
        }
    ],
    "double_ad": [
        {
            "source": "admob",
            "weight": 1,
            "type": "interstitial",
            "id": "ca-app-pub-3940256099942544/4411468910",
            "id2": "ca-app-pub-3940256099942544/4411468910"
        }
    ]
};

  static String get remoteConfigKey => 'ad_config_json';
}
// dart format on

class MyAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    final eventNameStr = event.eventName != null
        ? ' event=${event.eventName}'
        : '';
    // ignore: avoid_print
    print(
      '[my-ad-event] type=${event.eventType.name} placement=${event.placement} unit=${event.adUnitId}$eventNameStr',
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
