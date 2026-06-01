import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlacementAdSlot', () {
    test('hasAd returns true when ad is not null', () {
      const slot = PlacementAdSlot(
        placement: PlacementType('home'),
        ad: 'mock_ad_object',
      );
      expect(slot.hasAd, isTrue);
    });

    test('hasAd returns false when ad is null', () {
      const slot = PlacementAdSlot(
        placement: PlacementType('home'),
        ad: null,
      );
      expect(slot.hasAd, isFalse);
    });

    test('all fields are stored correctly', () {
      const slot = PlacementAdSlot(
        placement: PlacementType('home'),
        ad: 'ad_ref',
        loadedSource: AdSource.admob,
        loadedType: AdType.interstitial,
        adUnitId: 'unit-123',
        cacheKey: 'key-abc',
        loadedAt: null,
        isLoading: true,
        lastError: 'load_error',
      );
      expect(slot.placement, const PlacementType('home'));
      expect(slot.ad, 'ad_ref');
      expect(slot.loadedSource, AdSource.admob);
      expect(slot.loadedType, AdType.interstitial);
      expect(slot.adUnitId, 'unit-123');
      expect(slot.cacheKey, 'key-abc');
      expect(slot.isLoading, isTrue);
      expect(slot.lastError, 'load_error');
    });

    test('default isLoading is false', () {
      const slot = PlacementAdSlot(
        placement: PlacementType('home'),
      );
      expect(slot.isLoading, isFalse);
    });
  });

  group('PlacementAdPool', () {
    test('hasAd returns false for empty slots', () {
      const pool = PlacementAdPool(
        placement: PlacementType('home'),
        slots: [],
      );
      expect(pool.hasAd, isFalse);
    });

    test('hasAd returns true when slots are not empty', () {
      const pool = PlacementAdPool(
        placement: PlacementType('home'),
        slots: [
          PlacementAdSlot(
            placement: PlacementType('home'),
            ad: 'ad1',
          ),
        ],
      );
      expect(pool.hasAd, isTrue);
    });

    test('count returns number of slots', () {
      const pool = PlacementAdPool(
        placement: PlacementType('home'),
        slots: [
          PlacementAdSlot(placement: PlacementType('home'), ad: 'ad1'),
          PlacementAdSlot(placement: PlacementType('home'), ad: 'ad2'),
          PlacementAdSlot(placement: PlacementType('home'), ad: 'ad3'),
        ],
      );
      expect(pool.count, 3);
    });

    test('firstAd returns first slot ad', () {
      const pool = PlacementAdPool(
        placement: PlacementType('home'),
        slots: [
          PlacementAdSlot(placement: PlacementType('home'), ad: 'first'),
          PlacementAdSlot(placement: PlacementType('home'), ad: 'second'),
        ],
      );
      expect(pool.firstAd, 'first');
    });

    test('firstAd returns null for empty pool', () {
      const pool = PlacementAdPool(
        placement: PlacementType('home'),
        slots: [],
      );
      expect(pool.firstAd, isNull);
    });

    test('ads returns all ad objects filtering nulls', () {
      const pool = PlacementAdPool(
        placement: PlacementType('home'),
        slots: [
          PlacementAdSlot(placement: PlacementType('home'), ad: 'ad1'),
          PlacementAdSlot(placement: PlacementType('home'), ad: null),
          PlacementAdSlot(placement: PlacementType('home'), ad: 'ad3'),
        ],
      );
      final ads = pool.ads;
      expect(ads, hasLength(2));
      expect(ads, ['ad1', 'ad3']);
    });

    test('ads returns empty list when pool is empty', () {
      const pool = PlacementAdPool(
        placement: PlacementType('home'),
        slots: [],
      );
      expect(pool.ads, isEmpty);
    });

    test('default slots is empty list', () {
      const pool = PlacementAdPool(placement: PlacementType('home'));
      expect(pool.slots, isEmpty);
    });

    test('default isLoading is false', () {
      const pool = PlacementAdPool(placement: PlacementType('home'));
      expect(pool.isLoading, isFalse);
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
      final result = AdShowResult.success();
      expect(result.shown, isTrue);
      expect(result.error, isNull);
    });

    test('failure has shown=false and error', () {
      final result = AdShowResult.failure(Exception('show failed'));
      expect(result.shown, isFalse);
      expect(result.error, isNotNull);
    });

    test('failure without error defaults error to null', () {
      final result = AdShowResult.failure();
      expect(result.shown, isFalse);
      expect(result.error, isNull);
    });
  });

  group('NativeAdAttribution', () {
    test('stores all attribution fields', () {
      final attr = NativeAdAttribution(
        placement: const PlacementType('home'),
        placementLabel: 'inbox_top',
        eventName: 'first_load',
      );
      expect(attr.placement, const PlacementType('home'));
      expect(attr.placementLabel, 'inbox_top');
      expect(attr.eventName, 'first_load');
    });

    test('placementLabel is optional and defaults to null', () {
      final attr = NativeAdAttribution(
        placement: const PlacementType('home'),
        eventName: 'cold_start',
      );
      expect(attr.placementLabel, isNull);
    });

    test('fields are mutable', () {
      final attr = NativeAdAttribution(
        placement: const PlacementType('open'),
        eventName: 'initial',
      );
      attr.placement = const PlacementType('home');
      attr.placementLabel = 'updated';
      attr.eventName = 'changed';

      expect(attr.placement, const PlacementType('home'));
      expect(attr.placementLabel, 'updated');
      expect(attr.eventName, 'changed');
    });
  });
}
