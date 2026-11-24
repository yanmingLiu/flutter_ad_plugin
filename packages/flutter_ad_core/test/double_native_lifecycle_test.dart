import 'dart:async';

import 'package:flutter_ad_core/engine.dart';
import 'package:flutter_ad_core/models.dart';
import 'package:flutter_ad_core/platform.dart';
import 'package:flutter_test/flutter_test.dart';

const _placement = PlacementType('double_native');

class _Config implements AdConfigRepository {
  @override
  Future<AdConfig> getConfig() async => AdConfig(
    loadTimeoutSeconds: 1,
    adCdSeconds: 0,
    placements: {
      _placement: const [
        AdUnitConfig(
          source: AdSource.admob,
          weight: 2,
          type: AdType.doubleNative,
          id: 'first',
          poolSize: 2,
        ),
        AdUnitConfig(
          source: AdSource.admob,
          weight: 1,
          type: AdType.doubleNative,
          id: 'second',
        ),
      ],
    },
  );
}

class _Reporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {}
}

class _NativeAdapter implements InlineAdAdapter {
  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.native;

  final first = Object();
  final secondStarted = Completer<void>();
  final secondResult = Completer<AdLoadResult<Object>>();
  final disposed = <Object>[];
  void Function(Object ad, AdType type, String adUnitId)? lateCallback;

  @override
  Future<AdLoadResult<Object>> prepare({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback callback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    if (unit.id == 'first') {
      return AdLoadResult.success(ad: first, type: type, adUnitId: unit.id);
    }
    lateCallback = onLateAdLoaded;
    secondStarted.complete();
    return secondResult.future;
  }

  @override
  void dispose(Object ad) => disposed.add(ad);
}

void main() {
  for (final succeeds in [false, true]) {
    test(
      'DoubleNative publishes only a complete group (success=$succeeds)',
      () async {
        final adapter = _NativeAdapter();
        final cache = AdCacheService();
        final loader = AdLoaderService(
          configRepository: _Config(),
          adapterRegistry: AdAdapterRegistry(inlineAdapters: [adapter]),
          cache: cache,
          eventMapper: AdEventMapper(),
          reporter: _Reporter(),
        );
        addTearDown(loader.dispose);

        final loading = loader.preloadNative(_placement, eventName: 'test');
        await adapter.secondStarted.future;
        expect(cache.getSlots(_placement), isEmpty);

        final second = Object();
        adapter.secondResult.complete(
          succeeds
              ? AdLoadResult.success(
                  ad: second,
                  type: AdType.native,
                  adUnitId: 'second',
                )
              : AdLoadResult.failure(
                  type: AdType.native,
                  adUnitId: 'second',
                  error: TimeoutException('load'),
                ),
        );
        expect(await loading, succeeds);
        if (succeeds) {
          expect(cache.getSlots(_placement).map((slot) => slot.ad), [
            adapter.first,
            second,
          ]);
          expect(adapter.disposed, isEmpty);
        } else {
          expect(adapter.disposed, [adapter.first]);
          adapter.lateCallback!(second, AdType.native, 'second');
          expect(cache.getSlots(_placement), isEmpty);
          expect(adapter.disposed, [adapter.first, second]);
        }
      },
    );
  }
}
