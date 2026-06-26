import 'dart:io';

import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

class MyConfigRepository extends DefaultAdConfigRepository {
  MyConfigRepository() : super(localConfig: localConfig);

  static Map<String, dynamic> get localConfig {
    final ids = _AdMobTestIds.current;
    return {
      'load_timeout': 7,
      'same_placement_cd': 30,
      'different_placement_cd': 30,
      'common_placements': ['behavior', 'behavior2'],
      'high_value_placement': 'level_h',
      'open': [
        _fullscreenNativeUnit(ids),
        {'source': 'admob', 'weight': 3, 'type': 'open', 'id': ids.open},
        {
          'source': 'admob',
          'weight': 2,
          'type': 'interstitial',
          'id': ids.interstitial,
        },
      ],
      'home': [
        {
          'source': 'admob',
          'weight': 1,
          'type': 'native',
          'id': ids.native,
          'id2': ids.native,
          'template_type': 'medium',
          'refresh_minutes': 20,
        },
      ],
      'bottom_banner': [
        {
          'source': 'admob',
          'weight': 1,
          'type': 'banner',
          'id': ids.banner,
          'banner_size': 'banner',
          'banner_mode': 'global',
          'refresh_minutes': 30,
        },
      ],
      'article_inline_banner': [
        {
          'source': 'admob',
          'weight': 1,
          'type': 'banner',
          'ids': [ids.banner, ids.banner],
          'banner_size': 'banner',
          'banner_mode': 'inline',
        },
      ],
      'message': [
        _fullscreenNativeUnit(ids),
        {
          'source': 'admob',
          'weight': 2,
          'type': 'interstitial',
          'id': ids.interstitial,
          'load_timeout': 15,
        },
      ],
      'behavior': [
        _fullscreenNativeUnit(ids),
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'interstitial',
          'ad_id': ids.interstitial,
        },
      ],
      'behavior2': [
        _fullscreenNativeUnit(ids),
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'rewarded',
          'ad_id': ids.rewarded,
        },
      ],
      'level_h': [
        _fullscreenNativeUnit(ids),
        {
          'ad_source': 'admob',
          'ad_weight': 1,
          'ad_type': 'interstitial',
          'ad_id': ids.interstitial,
        },
      ],
      'play_middle': [
        _fullscreenNativeUnit(ids),
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
          'ad_id2': ids.native,
        },
      ],
    };
  }

  static String get remoteConfigKey => 'ad_config_json';

  static Map<String, dynamic> _fullscreenNativeUnit(_AdMobTestIds ids) => {
    'source': 'admob',
    'weight': 4,
    'type': 'native',
    'id': ids.nativeVideo,
    // native_factory_id 可选：自定义原生广告工厂ID（Android/iOS 需先注册对应 NativeAdFactory）
    // 'native_factory_id': 'my_custom_factory',
  };
}

Map<PlacementType, PlacementPolicy> buildPlacementPolicies() {
  return {
    const PlacementType('open'): const PlacementPolicy(
      isFullscreen: true,
      applySamePlacementCd: true,
      applyDifferentPlacementCd: true,
      contributesToGlobalCooldown: true,
      showNotReadyToast: false,
      waitForLoadOnShow: true,
      preferHighValueOnShow: false,
    ),
    const PlacementType('message'): const PlacementPolicy(
      isFullscreen: true,
      applySamePlacementCd: false,
      applyDifferentPlacementCd: false,
      contributesToGlobalCooldown: false,
      showNotReadyToast: true,
      waitForLoadOnShow: true,
      preferHighValueOnShow: true,
      notReadyMsg: 'Ad is still loading, please wait a moment.',
    ),
  };
}

class _AdMobTestIds {
  const _AdMobTestIds({
    required this.open,
    required this.interstitial,
    required this.rewarded,
    required this.native,
    required this.nativeVideo,
    required this.banner,
  });

  final String open;
  final String interstitial;
  final String rewarded;
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
    native: 'ca-app-pub-3940256099942544/2247696110',
    nativeVideo: 'ca-app-pub-3940256099942544/1044960115',
    banner: 'ca-app-pub-3940256099942544/6300978111',
  );

  static const ios = _AdMobTestIds(
    open: 'ca-app-pub-3940256099942544/5575463023',
    interstitial: 'ca-app-pub-3940256099942544/4411468910',
    rewarded: 'ca-app-pub-3940256099942544/1712485313',
    native: 'ca-app-pub-3940256099942544/3986624511',
    nativeVideo: 'ca-app-pub-3940256099942544/2521693316',
    banner: 'ca-app-pub-3940256099942544/2934735716',
  );
}

class MyAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
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
