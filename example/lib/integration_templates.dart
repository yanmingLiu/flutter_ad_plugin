import 'dart:io';

import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

class MyConfigRepository extends DefaultAdConfigRepository {
  MyConfigRepository() : super(localConfig: localConfig);

  static Map<String, dynamic> get localConfig {
    final ids = _AdMobTestIds.current;
    return {
      'ad_cd': 0,
      'load_timeout': 7,
      'rewarded_load_timeout': 20,
      'common_placements': ['behavior', 'behavior2'],
      'high_value_placement': 'level_h',
      'open': [
        {'source': 'admob', 'weight': 3, 'type': 'open', 'id': ids.open},
        {
          'source': 'admob',
          'weight': 2,
          'type': 'interstitial',
          'ad_id': ids.interstitial,
        },
        {
          'source': 'admob',
          'weight': 1,
          'type': 'rewarded',
          'ad_id': ids.rewarded,
        },
        {'source': 'admob', 'weight': 4, 'type': 'native', 'ad_id': ids.native},
      ],
      'home': [
        {
          'source': 'admob',
          'weight': 1,
          'type': 'native',
          'id': ids.native,
          'template_type': 'medium',
        },
      ],
      'behavior': [
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'interstitial',
          'ad_id': ids.interstitial,
        },
      ],
      'behavior2': [
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'native',
          'ad_id': ids.native,
        },
      ],
      'level_h': [
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'rewarded_interstitial',
          'ad_id': ids.rewardedInterstitial,
        },
      ],
      'play_middle': [
        {
          'ad_source': 'admob',
          'ad_weight': 2,
          'ad_type': 'interstitial',
          'ad_id': ids.interstitial,
        },
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'double_native',
          'ad_id': ids.native,
          'ad_id2': ids.nativeVideo,
        },
      ],
      'bottom_banner': [
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'banner',
          'ad_id': ids.banner,
          'banner_mode': 'global',
        },
      ],
      'article_inline_banner': [
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'banner',
          'ad_id': ids.banner,
          'banner_mode': 'inline',
        },
      ],
    };
  }

  static String get remoteConfigKey => 'ad_config_json';
}

Map<PlacementType, PlacementPolicy> buildPlacementPolicies() {
  return const {};
}

class _AdMobTestIds {
  const _AdMobTestIds({
    required this.open,
    required this.interstitial,
    required this.rewarded,
    required this.rewardedInterstitial,
    required this.native,
    required this.nativeVideo,
    required this.banner,
  });

  final String open;
  final String interstitial;
  final String rewarded;
  final String rewardedInterstitial;
  final String native;
  final String nativeVideo;
  final String banner;

  static _AdMobTestIds get current {
    return Platform.isAndroid ? android : ios;
  }

  static const android = _AdMobTestIds(
    open: 'ca-app-pub-3940256099942544/9257395921',
    interstitial: 'ca-app-pub-3940256099942544/1033173712',
    rewarded: 'ca-app-pub-3940256099942544/5224354917',
    rewardedInterstitial: 'ca-app-pub-3940256099942544/5354046379',
    native: 'ca-app-pub-3940256099942544/2247696110',
    nativeVideo: 'ca-app-pub-3940256099942544/1044960115',
    banner: 'ca-app-pub-3940256099942544/6300978111',
  );

  static const ios = _AdMobTestIds(
    open: 'ca-app-pub-3940256099942544/5575463023',
    interstitial: 'ca-app-pub-3940256099942544/4411468910',
    rewarded: 'ca-app-pub-3940256099942544/1712485313',
    rewardedInterstitial: 'ca-app-pub-3940256099942544/6978759866',
    native: 'ca-app-pub-3940256099942544/3986624511',
    nativeVideo: 'ca-app-pub-3940256099942544/2521693316',
    banner: 'ca-app-pub-3940256099942544/2934735716',
  );
}

class MyAdEventReporter implements AdEventReporter {
  MyAdEventReporter({this.onEvent});

  final void Function(AdEvent event)? onEvent;

  @override
  Future<void> report(AdEvent event) async {
    onEvent?.call(event);
    // 示例：将广告收入上报至 Facebook
    // if (event.eventType == AdEventType.income && event.revenue != null) {
    //   FacebookSDKUtil.logAdImpression(
    //     value: event.revenue!,
    //     currency: event.currency ?? 'USD',
    //     adType: event.adType?.name,
    //     adScreen: event.eventName,
    //     adSource: event.source?.name,
    //     adUnitId: event.adUnitId,
    //   );
    // }

    // 示例：将广告事件上报至 Firebase Analytics
    // FirebaseAnalytics.instance.logEvent(
    //   name: 'ad_${event.eventName}',
    //   parameters: {
    //     if (event.source != null) 'ad_source': event.source!.name,
    //     if (event.adType != null) 'ad_type': event.adType!.name,
    //     if (event.adUnitId != null) 'ad_unit_id': event.adUnitId,
    //     if (event.eventType != null) 'event_type': event.eventType!.name,
    //     if (event.revenue != null) 'revenue': event.revenue,
    //     if (event.currency != null) 'currency': event.currency,
    //   },
    // );
  }
}
