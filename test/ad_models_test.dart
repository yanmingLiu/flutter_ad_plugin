import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdSlotLoaded', () {
    test('stores all fields correctly', () {
      final slot = AdSlotLoaded(
        placement: const PlacementType('home'),
        ad: 'ad_ref',
        source: AdSource.admob,
        type: AdType.interstitial,
        adUnitId: 'unit-123',
        cacheKey: 'key-abc',
        loadedAt: DateTime(2025),
      );
      expect(slot.placement.name, 'home');
      expect(slot.ad, 'ad_ref');
      expect(slot.source, AdSource.admob);
      expect(slot.type, AdType.interstitial);
      expect(slot.adUnitId, 'unit-123');
      expect(slot.cacheKey, 'key-abc');
    });

    test('attribution is optional', () {
      final slot = AdSlotLoaded(
        placement: const PlacementType('home'),
        ad: 'ad_ref',
        source: AdSource.admob,
        type: AdType.native,
        adUnitId: 'unit-1',
        cacheKey: 'key-1',
        loadedAt: DateTime(2025),
      );
      expect(slot.attribution, isNull);
    });

    test('sealed class type checking works', () {
      final slot = AdSlotLoaded(
        placement: const PlacementType('home'),
        ad: 'ad_ref',
        source: AdSource.admob,
        type: AdType.native,
        adUnitId: 'unit-1',
        cacheKey: 'key-1',
        loadedAt: DateTime(2025),
      );
      expect(slot, isA<AdSlotLoaded>());
      expect(slot, isA<AdSlotState>());
    });
  });

  group('AdSlotFailed', () {
    test('stores error info', () {
      final slot = AdSlotFailed(
        placement: const PlacementType('home'),
        cacheKey: 'key-abc',
        error: 'timeout',
      );
      expect(slot.placement.name, 'home');
      expect(slot.cacheKey, 'key-abc');
      expect(slot.error, 'timeout');
      expect(slot, isA<AdSlotFailed>());
      expect(slot, isA<AdSlotState>());
    });

    test('error and cacheKey are optional', () {
      final slot = AdSlotFailed(placement: const PlacementType('home'));
      expect(slot.error, isNull);
      expect(slot.cacheKey, isNull);
    });
  });

  group('AdLoadResult', () {
    test('success result has ad and isSuccess is true', () {
      final result = AdLoadResult<String>.success(
        ad: 'loaded_ad',
        type: AdType.interstitial,
        adUnitId: 'unit-1',
      );
      expect(result.isSuccess, isTrue);
      expect(result.ad, 'loaded_ad');
      expect(result.type, AdType.interstitial);
      expect(result.adUnitId, 'unit-1');
      expect(result.error, isNull);
    });

    test('failure result has error and isSuccess is false', () {
      final result = AdLoadResult<String>.failure(
        type: AdType.rewarded,
        adUnitId: 'unit-2',
        error: Exception('timeout'),
      );
      expect(result.isSuccess, isFalse);
      expect(result.ad, isNull);
      expect(result.type, AdType.rewarded);
      expect(result.adUnitId, 'unit-2');
      expect(result.error, isNotNull);
    });
  });

  group('AdShowResult', () {
    test('success has shown=true and no error', () {
      final result = AdShowResult.success(
        requestedPlacement: const PlacementType('open'),
        shownPlacement: const PlacementType('level_h'),
        source: AdSource.admob,
        type: AdType.interstitial,
        adUnitId: 'unit-1',
      );
      expect(result.shown, isTrue);
      expect(result.error, isNull);
      expect(result.requestedPlacement, const PlacementType('open'));
      expect(result.shownPlacement, const PlacementType('level_h'));
      expect(result.source, AdSource.admob);
      expect(result.type, AdType.interstitial);
      expect(result.adUnitId, 'unit-1');
    });

    test('failure has shown=false and error', () {
      final result = AdShowResult.failure(
        error: Exception('show failed'),
        requestedPlacement: const PlacementType('open'),
        errorReason: 'show_failed',
      );
      expect(result.shown, isFalse);
      expect(result.error, isNotNull);
      expect(result.errorReason, 'show_failed');
    });
  });

  test('AdSequenceShowResult reports aggregate and individual results', () {
    final result = AdSequenceShowResult(
      requestedPlacement: const PlacementType('behavior'),
      results: [
        AdShowResult.success(
          shownPlacement: const PlacementType('level_h'),
          adUnitId: 'high-id',
        ),
        AdShowResult.failure(errorReason: 'show_failed'),
      ],
      errorReason: 'show_failed',
    );

    expect(result.shown, isTrue);
    expect(result.shownCount, 1);
    expect(result.results, hasLength(2));
  });

  group('AdAttribution', () {
    test('stores all attribution fields', () {
      final attr = AdAttribution(
        placement: const PlacementType('home'),
        eventName: 'first_load',
      );
      expect(attr.placement.name, 'home');
      expect(attr.eventName, 'first_load');
    });

    test('fields are mutable', () {
      final attr = AdAttribution(
        placement: const PlacementType('open'),
        eventName: 'initial',
      );
      attr.placement = const PlacementType('home');
      attr.eventName = 'changed';

      expect(attr.placement.name, 'home');
      expect(attr.eventName, 'changed');
    });
  });
}
