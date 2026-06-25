import 'package:flutter/widgets.dart';
import 'package:flutter_ad_plugin/src/core/ad_config.dart';
import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_ad_plugin/src/platform/ad_adapter.dart';
import 'package:flutter_ad_plugin/src/platform/ad_registry.dart';
import 'package:flutter_ad_plugin/src/utils/ad_reporter.dart';
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
    required AdEventReporter reporter,
    required String eventName,
    bool renderAsFullscreen = false,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    return AdLoadResult.success(ad: Object(), type: _type, adUnitId: unit.id);
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    AdFullScreenNativeStyle style = const AdFullScreenNativeStyle(),
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
    test('retrieves registered adapter by source and type', () {
      final adapter = _FakeAdapter(AdSource.admob, AdType.open);
      final registry = AdAdapterRegistry([adapter]);

      final retrieved = registry.get(AdSource.admob, AdType.open);
      expect(retrieved, same(adapter));
    });

    test('retrieves correct adapter among multiple', () {
      final openAdapter = _FakeAdapter(AdSource.admob, AdType.open);
      final interstitialAdapter = _FakeAdapter(
        AdSource.admob,
        AdType.interstitial,
      );
      final rewardedAdapter = _FakeAdapter(AdSource.admob, AdType.rewarded);
      final nativeAdapter = _FakeAdapter(AdSource.admob, AdType.native);

      final registry = AdAdapterRegistry([
        openAdapter,
        interstitialAdapter,
        rewardedAdapter,
        nativeAdapter,
      ]);

      expect(registry.get(AdSource.admob, AdType.open), same(openAdapter));
      expect(
        registry.get(AdSource.admob, AdType.interstitial),
        same(interstitialAdapter),
      );
      expect(
        registry.get(AdSource.admob, AdType.rewarded),
        same(rewardedAdapter),
      );
      expect(registry.get(AdSource.admob, AdType.native), same(nativeAdapter));
    });

    test('throws StateError for unregistered source+type combination', () {
      final adapter = _FakeAdapter(AdSource.admob, AdType.open);
      final registry = AdAdapterRegistry([adapter]);

      expect(
        () => registry.get(AdSource.max, AdType.interstitial),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError for unregistered type of known source', () {
      final adapter = _FakeAdapter(AdSource.admob, AdType.open);
      final registry = AdAdapterRegistry([adapter]);

      expect(
        () => registry.get(AdSource.admob, AdType.interstitial),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError for unregistered source of known type', () {
      final adapter = _FakeAdapter(AdSource.admob, AdType.open);
      final registry = AdAdapterRegistry([adapter]);

      expect(
        () => registry.get(AdSource.max, AdType.open),
        throwsA(isA<StateError>()),
      );
    });

    test('error message includes source and type names', () {
      final registry = AdAdapterRegistry([]);

      expect(
        () => registry.get(AdSource.admob, AdType.open),
        throwsA(
          predicate<StateError>((e) {
            final msg = e.toString();
            return msg.contains('admob') && msg.contains('open');
          }),
        ),
      );
    });
  });

  group('AdSdkInitializer', () {
    test('supports returns true for registered source', () {
      final initializer = _FakeSdkInitializer(AdSource.admob);
      final sdkInit = AdSdkInitializer([initializer]);

      expect(sdkInit.supports(AdSource.admob), isTrue);
    });

    test('supports returns false for unregistered source', () {
      final initializer = _FakeSdkInitializer(AdSource.admob);
      final sdkInit = AdSdkInitializer([initializer]);

      expect(sdkInit.supports(AdSource.max), isFalse);
    });

    test('initSource throws StateError for unregistered source', () {
      final initializer = _FakeSdkInitializer(AdSource.admob);
      final sdkInit = AdSdkInitializer([initializer]);

      expect(
        () => sdkInit.initSource(AdSource.max),
        throwsA(isA<StateError>()),
      );
    });

    test('initSource succeeds for registered source', () {
      final initializer = _FakeSdkInitializer(AdSource.admob);
      final sdkInit = AdSdkInitializer([initializer]);

      expect(sdkInit.initSource(AdSource.admob), completes);
    });

    test('initAll initializes all registered sources', () async {
      final admobInit = _FakeSdkInitializer(AdSource.admob);
      final sdkInit = AdSdkInitializer([admobInit]);

      await sdkInit.initAll();
      // Should complete without error
    });
  });
}
