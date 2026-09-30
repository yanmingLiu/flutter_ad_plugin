import 'platform_test_config.dart';

Map<String, dynamic> get localAdConfig {
  final platform = selectedPlatformTestConfig;
  final source = platform.source;
  final rewardedType = platform.platform == AdTestPlatform.admob
      ? 'rewarded_interstitial'
      : 'rewarded';
  return {
    'ad_cd': 0,
    'load_timeout': 7,
    'rewarded_load_timeout': 20,
    'common_placements': ['behavior', 'behavior2'],
    'high_value_placement': 'level_h',
    'open': [
      {'source': source, 'weight': 4, 'type': 'open', 'id': platform.openId},
      {
        'source': source,
        'weight': 3,
        'type': 'interstitial',
        'ad_id': platform.interstitialId,
      },
      {
        'source': source,
        'weight': 2,
        'type': 'rewarded',
        'ad_id': platform.rewardedId,
      },
      {
        'source': source,
        'weight': 1,
        'type': 'native',
        'ad_id': platform.nativeId,
      },
    ],
    'home': [
      {
        'source': source,
        'weight': 1,
        'type': 'native',
        'id': platform.nativeId,
        'template_type': 'medium',
      },
    ],
    'behavior': [
      {
        'ad_source': source,
        'ad_weight': 1,
        'ad_type': 'interstitial',
        'ad_id': platform.interstitialId,
      },
    ],
    'behavior2': [
      {
        'ad_source': source,
        'ad_weight': 1,
        'ad_type': 'native',
        'ad_id': platform.nativeId,
      },
    ],
    'level_h': [
      {
        'ad_source': source,
        'ad_weight': 1,
        'ad_type': rewardedType,
        'ad_id': platform.rewardedInterstitialId,
      },
    ],
    'play_middle': [
      {
        'ad_source': source,
        'ad_weight': 2,
        'ad_type': 'interstitial',
        'ad_id': platform.interstitialId,
      },
      {
        'ad_source': source,
        'ad_weight': 1,
        'ad_type': 'double_native',
        'ad_id': platform.nativeId,
        'ad_id2': platform.nativeVideoId,
      },
    ],
    'bottom_banner': [
      {
        'ad_source': source,
        'ad_weight': 1,
        'ad_type': 'banner',
        'ad_id': platform.bannerId,
        'banner_mode': 'global',
      },
    ],
    'article_inline_banner': [
      {
        'ad_source': source,
        'ad_weight': 1,
        'ad_type': 'banner',
        'ad_id': platform.bannerId,
        'banner_mode': 'inline',
      },
    ],
  };
}
