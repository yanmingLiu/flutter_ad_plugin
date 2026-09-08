import 'package:flutter/widgets.dart';
import 'package:flutter_ad_plugin/src/core/ad_config.dart';
import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_ad_plugin/src/platform/ad_adapter.dart';
import 'package:flutter_ad_plugin/src/platform/ad_callback.dart';
import 'package:flutter_ad_plugin/src/platform/ad_registry.dart';
import 'package:flutter_ad_plugin/src/utils/cancellation_token.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements AdTypeAdapter {
  final AdSource _source;
  final AdType _type;

  const _FakeAdapter(this._source, this._type);

  @override
  AdSource get source => _source;

  @override
  AdType get type => _type;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    return AdLoadResult.success(ad: Object(), type: _type, adUnitId: unit.id);
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    required String eventName,
    required Object ad,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    void Function(AdRawCallback)? onCallback,
  }) async {
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {}
}

class _FakeSdkInitializer implements AdSourceSdkInitializer {
  final AdSource _source;
  _FakeSdkInitializer(this._source);

  @override
  AdSource get source => _source;

  @override
  Future<void> init() async {}
}

void main() {
  group('AdAdapterRegistry', () {
    test('returns adapter registered by source+type', () {
      final adapter = _FakeAdapter(AdSource.admob, AdType.interstitial);
      final registry = AdAdapterRegistry([adapter]);

      final result = registry.get(AdSource.admob, AdType.interstitial);
      expect(result, same(adapter));
    });

    test('stores multiple adapters', () {
      final openAdapter = _FakeAdapter(AdSource.admob, AdType.open);
      final rewardedAdapter = _FakeAdapter(AdSource.admob, AdType.rewarded);
      final registry = AdAdapterRegistry([openAdapter, rewardedAdapter]);

      expect(registry.get(AdSource.admob, AdType.open), same(openAdapter));
      expect(
        registry.get(AdSource.admob, AdType.rewarded),
        same(rewardedAdapter),
      );
    });

    test('supports rewarded interstitial adapter type', () {
      final adapter = _FakeAdapter(AdSource.admob, AdType.rewardedInterstitial);
      final registry = AdAdapterRegistry([adapter]);

      expect(
        registry.get(AdSource.admob, AdType.rewardedInterstitial),
        same(adapter),
      );
      expect(AdType.rewardedInterstitial.isFullscreen, isTrue);
    });

    test('throws StateError for unregistered adapter', () {
      final registry = AdAdapterRegistry([
        _FakeAdapter(AdSource.admob, AdType.interstitial),
      ]);
      expect(
        () => registry.get(AdSource.admob, AdType.open),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AdSdkInitializer', () {
    test('initAll calls init on all initializers', () async {
      final initializer = _FakeSdkInitializer(AdSource.admob);
      final sdk = AdSdkInitializer([initializer]);
      await sdk.initAll();
    });

    test('supports returns true for registered source', () {
      final initializer = _FakeSdkInitializer(AdSource.admob);
      final sdk = AdSdkInitializer([initializer]);
      expect(sdk.supports(AdSource.admob), isTrue);
      expect(sdk.supports(AdSource.max), isFalse);
    });
  });
}
