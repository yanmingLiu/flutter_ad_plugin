import 'dart:io';

enum AdTestPlatform { admob, max, topon }

class PlatformTestConfig {
  const PlatformTestConfig({
    required this.platform,
    required this.source,
    required this.openId,
    required this.interstitialId,
    required this.rewardedId,
    required this.rewardedInterstitialId,
    required this.nativeId,
    required this.nativeVideoId,
    required this.bannerId,
    this.sdkKey = '',
    this.appId = '',
    this.appKey = '',
    this.debugKey = '',
    this.testDeviceAdvertisingIds = const [],
  });

  final AdTestPlatform platform;
  final String source;
  final String openId;
  final String interstitialId;
  final String rewardedId;
  final String rewardedInterstitialId;
  final String nativeId;
  final String nativeVideoId;
  final String bannerId;
  final String sdkKey;
  final String appId;
  final String appKey;
  final String debugKey;
  final List<String> testDeviceAdvertisingIds;

  String get displayName => switch (platform) {
    AdTestPlatform.admob => 'AdMob',
    AdTestPlatform.max => 'AppLovin MAX',
    AdTestPlatform.topon => 'TopOn',
  };

  List<String> get missingRequiredValues {
    final missing = switch (platform) {
      AdTestPlatform.admob => <String>[],
      AdTestPlatform.max => _missing([
        ('MAX_SDK_KEY', sdkKey),
        ('MAX_OPEN_AD_UNIT_ID', openId),
        ('MAX_INTERSTITIAL_AD_UNIT_ID', interstitialId),
        ('MAX_REWARDED_AD_UNIT_ID', rewardedId),
        ('MAX_NATIVE_AD_UNIT_ID', nativeId),
        ('MAX_NATIVE_VIDEO_AD_UNIT_ID', nativeVideoId),
        ('MAX_BANNER_AD_UNIT_ID', bannerId),
      ]),
      AdTestPlatform.topon => _missing([
        ('TOPON_APP_ID', appId),
        ('TOPON_APP_KEY', appKey),
        ('TOPON_SPLASH_PLACEMENT_ID', openId),
        ('TOPON_INTERSTITIAL_PLACEMENT_ID', interstitialId),
        ('TOPON_REWARDED_PLACEMENT_ID', rewardedId),
        ('TOPON_NATIVE_PLACEMENT_ID', nativeId),
        ('TOPON_NATIVE_VIDEO_PLACEMENT_ID', nativeVideoId),
        ('TOPON_BANNER_PLACEMENT_ID', bannerId),
      ]),
    };
    return List.unmodifiable(missing);
  }

  static List<String> _missing(List<(String, String)> values) {
    return [
      for (final (name, value) in values)
        if (value.trim().isEmpty) name,
    ];
  }
}

const _selectedPlatformName = String.fromEnvironment(
  'AD_PLATFORM',
  defaultValue: 'admob',
);

AdTestPlatform get selectedAdTestPlatform {
  return switch (_selectedPlatformName.trim().toLowerCase()) {
    'admob' => AdTestPlatform.admob,
    'max' => AdTestPlatform.max,
    'topon' => AdTestPlatform.topon,
    _ => throw ArgumentError.value(
      _selectedPlatformName,
      'AD_PLATFORM',
      'Expected admob, max, or topon',
    ),
  };
}

PlatformTestConfig get selectedPlatformTestConfig {
  return switch (selectedAdTestPlatform) {
    AdTestPlatform.admob => _admobConfig,
    AdTestPlatform.max => _maxConfig,
    AdTestPlatform.topon => _toponConfig,
  };
}

PlatformTestConfig get _admobConfig {
  final ids = _AdMobTestIds.current;
  return PlatformTestConfig(
    platform: AdTestPlatform.admob,
    source: 'admob',
    openId: ids.open,
    interstitialId: ids.interstitial,
    rewardedId: ids.rewarded,
    rewardedInterstitialId: ids.rewardedInterstitial,
    nativeId: ids.native,
    nativeVideoId: ids.nativeVideo,
    bannerId: ids.banner,
  );
}

PlatformTestConfig get _maxConfig {
  return PlatformTestConfig(
    platform: AdTestPlatform.max,
    source: 'max',
    sdkKey: const String.fromEnvironment('MAX_SDK_KEY'),
    openId: const String.fromEnvironment('MAX_OPEN_AD_UNIT_ID'),
    interstitialId: const String.fromEnvironment('MAX_INTERSTITIAL_AD_UNIT_ID'),
    rewardedId: const String.fromEnvironment('MAX_REWARDED_AD_UNIT_ID'),
    rewardedInterstitialId: const String.fromEnvironment(
      'MAX_REWARDED_AD_UNIT_ID',
    ),
    nativeId: const String.fromEnvironment('MAX_NATIVE_AD_UNIT_ID'),
    nativeVideoId: const String.fromEnvironment('MAX_NATIVE_VIDEO_AD_UNIT_ID'),
    bannerId: const String.fromEnvironment('MAX_BANNER_AD_UNIT_ID'),
    testDeviceAdvertisingIds: _maxTestDeviceIds,
  );
}

const _toponConfig = PlatformTestConfig(
  platform: AdTestPlatform.topon,
  source: 'topon',
  appId: String.fromEnvironment('TOPON_APP_ID'),
  appKey: String.fromEnvironment('TOPON_APP_KEY'),
  debugKey: String.fromEnvironment('TOPON_DEBUG_KEY'),
  openId: String.fromEnvironment('TOPON_SPLASH_PLACEMENT_ID'),
  interstitialId: String.fromEnvironment('TOPON_INTERSTITIAL_PLACEMENT_ID'),
  rewardedId: String.fromEnvironment('TOPON_REWARDED_PLACEMENT_ID'),
  rewardedInterstitialId: String.fromEnvironment('TOPON_REWARDED_PLACEMENT_ID'),
  nativeId: String.fromEnvironment('TOPON_NATIVE_PLACEMENT_ID'),
  nativeVideoId: String.fromEnvironment('TOPON_NATIVE_VIDEO_PLACEMENT_ID'),
  bannerId: String.fromEnvironment('TOPON_BANNER_PLACEMENT_ID'),
);

const _maxTestDeviceIdsValue = String.fromEnvironment(
  'MAX_TEST_DEVICE_ADVERTISING_IDS',
);

final List<String> _maxTestDeviceIds = List.unmodifiable(
  _maxTestDeviceIdsValue
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty),
);

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
