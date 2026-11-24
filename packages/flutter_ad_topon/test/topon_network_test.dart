import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ad_topon/flutter_ad_topon.dart';
import 'package:secmtp_sdk/at_index.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('reads the first cached ad after an empty load callback', () async {
    final hub = TopOnEventHub()..install();
    addTearDown(hub.dispose);
    final messenger = binding.defaultBinaryMessenger;
    const channel = AnythinkSdk.channel;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadInterstitialAd') {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('InterstitialCall', {
              'callbackName': 'interstitialAdDidFinishLoading',
              'placementID': 'test-interstitial',
              'requestMessage': 'succeed',
              'extraDic': {},
            }),
          ),
          (_) {},
        );
        return 'success';
      }
      expect(call.method, 'getInterstitialValidAds');
      expect(call.arguments, {'placementID': 'test-interstitial'});
      return '[{"publisher_revenue":"0.0025","network_name":"Pangle"},'
          '{"publisher_revenue":0.9,"network_name":"AdMob"}]';
    });

    final adapter = TopOnFullscreenAdapter(
      type: AdType.interstitial,
      eventHub: hub,
    );
    final result = await adapter.load(
      placement: const PlacementType('test'),
      unit: const AdUnitConfig(
        source: AdSource.topon,
        weight: 1,
        type: AdType.interstitial,
        id: 'test-interstitial',
      ),
      timeout: const Duration(seconds: 3),
      eventName: 'test',
    );
    expect(result.isSuccess, isTrue);
    expect(result.network, 'Pangle');
    expect((result.ad as TopOnFullscreenHandle).estimatedRevenue, 2500);
  });

  test('uses SDK-shaped TopOn options for banner and native ads', () {
    final sizeKey = ATCommon.getAdSizeKey();
    final adaptiveKey = ATNativeManager.isAdaptiveHeight();
    final bannerSize = ATBannerManager.createLoadBannerAdSize(300, 60);
    final banner = TopOnBannerOptions.fromUnit(
      AdUnitConfig(
        source: AdSource.topon,
        weight: 1,
        type: AdType.banner,
        id: 'banner',
        options: {
          'sceneID': 'scene',
          'width': 999,
          'extraMap': {sizeKey: bannerSize, 'sdkFlag': true},
        },
      ),
    );
    expect(banner.sceneId, 'scene');
    expect(banner.size, bannerSize);
    expect(banner.extraMap, {sizeKey: bannerSize, 'sdkFlag': true});

    final native = TopOnNativeOptions.fromUnit(
      AdUnitConfig(
        source: AdSource.topon,
        weight: 1,
        type: AdType.native,
        id: 'native',
        options: {
          'sceneId': 'old-scene',
          'extra_map': {'ignored': true},
          'extraMap': {adaptiveKey: true},
        },
      ),
    );
    expect(native.sceneId, isNull);
    expect(native.isAdaptiveHeight, isTrue);
    expect(native.extraMap, {
      ATCommon.isNativeShow(): false,
      sizeKey: ATNativeManager.createNativeSubViewAttribute(300, 250),
      adaptiveKey: true,
    });
  });

  test('paid callbacks use the network name and ignore firm IDs', () {
    final ad = Object();
    final paid = topOnPaidCallback(ad, {
      'publisher_revenue': '0.01',
      'currency': 'EUR',
    });
    expect(paid?.valueMicros, 10000);
    expect(paid?.currencyCode, 'EUR');
    expect(topOnPaidCallback(ad, {'ecpm': 0.01, 'currency': 'USD'}), isNull);
    expect(topOnPaidCallback(ad, {'publisher_revenue': 0.01}), isNull);
    expect(
      topOnPaidCallback(ad, {
        'publisher_revenue': 0.01,
        'currency': 'USD',
        'network_name': ' Custom ',
        'network_firm_id': 2,
      })?.network,
      'Custom',
    );
    final withoutName = topOnPaidCallback(ad, {
      'publisher_revenue': 0.01,
      'currency': 'USD',
      'network_firm_id': 2,
    });
    expect(withoutName, isNotNull);
    expect(withoutName?.network, isNull);
  });
}
