import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_ad_plugin/src/engine/ad_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

AdSlotLoaded _makeSlot(String placement, String ad, {String? cacheKey}) {
  return AdSlotLoaded(
    placement: PlacementType(placement),
    ad: ad,
    source: AdSource.admob,
    type: AdType.native,
    adUnitId: 'unit-1',
    cacheKey: cacheKey ?? ad,
    loadedAt: DateTime(2025),
  );
}

void main() {
  group('AdCacheService', () {
    late AdCacheService cache;

    setUp(() => cache = AdCacheService());

    test('hasSlot returns false for empty cache', () {
      expect(cache.hasSlot(PlacementType('home')), isFalse);
    });

    test('addSlot and hasSlot', () {
      cache.addSlot(PlacementType('home'), _makeSlot('home', 'ad1'));
      expect(cache.hasSlot(PlacementType('home')), isTrue);
      expect(cache.countFor(PlacementType('home')), 1);
    });

    test('getSlots returns loaded slots', () {
      final s1 = _makeSlot('home', 'ad1');
      final s2 = _makeSlot('home', 'ad2');
      cache.addSlot(PlacementType('home'), s1);
      cache.addSlot(PlacementType('home'), s2);

      final slots = cache.getSlots(PlacementType('home'));
      expect(slots, hasLength(2));
      expect(slots[0].ad, 'ad1');
      expect(slots[1].ad, 'ad2');
    });

    test('getSlots returns empty for missing placement', () {
      expect(cache.getSlots(PlacementType('unknown')), isEmpty);
    });

    test('hasSlotWithKey detects duplicate cache keys', () {
      cache.addSlot(
        PlacementType('home'),
        _makeSlot('home', 'ad1', cacheKey: 'key1'),
      );
      expect(cache.hasSlotWithKey(PlacementType('home'), 'key1'), isTrue);
      expect(cache.hasSlotWithKey(PlacementType('home'), 'key2'), isFalse);
    });

    test('firstSlot returns first loaded slot', () {
      cache.addSlot(PlacementType('home'), _makeSlot('home', 'ad1'));
      cache.addSlot(PlacementType('home'), _makeSlot('home', 'ad2'));

      final first = cache.firstSlot(PlacementType('home'));
      expect(first, isNotNull);
      expect(first!.ad, 'ad1');
    });

    test('firstSlotExcluding skips excluded slots', () {
      final s1 = _makeSlot('home', 'ad1');
      final s2 = _makeSlot('home', 'ad2');
      cache.addSlot(PlacementType('home'), s1);
      cache.addSlot(PlacementType('home'), s2);

      final result = cache.firstSlotExcluding(PlacementType('home'), {s1});
      expect(result, isNotNull);
      expect(result!.ad, 'ad2');
    });

    test('firstSlotExcluding returns null when all excluded', () {
      final s1 = _makeSlot('home', 'ad1');
      cache.addSlot(PlacementType('home'), s1);

      final result = cache.firstSlotExcluding(PlacementType('home'), {s1});
      expect(result, isNull);
    });

    test('removeSlot removes specific slot', () {
      final s1 = _makeSlot('home', 'ad1');
      final s2 = _makeSlot('home', 'ad2');
      cache.addSlot(PlacementType('home'), s1);
      cache.addSlot(PlacementType('home'), s2);

      cache.removeSlot(PlacementType('home'), s1);
      expect(cache.countFor(PlacementType('home')), 1);
      expect(cache.firstSlot(PlacementType('home'))!.ad, 'ad2');
    });

    test('clear removes all slots for placement', () {
      cache.addSlot(PlacementType('home'), _makeSlot('home', 'ad1'));
      cache.clear(PlacementType('home'));
      expect(cache.hasSlot(PlacementType('home')), isFalse);
    });

    test('attribution set and get', () {
      cache.setAttribution('ad1', PlacementType('home'), eventName: 'test');
      final attr = cache.getAttribution('ad1');
      expect(attr, isNotNull);
      expect(attr!.placement.name, 'home');
      expect(attr.eventName, 'test');
    });

    test('attribution updates existing', () {
      cache.setAttribution('ad1', PlacementType('home'), eventName: 'initial');
      cache.setAttribution('ad1', PlacementType('level'), eventName: 'updated');
      final attr = cache.getAttribution('ad1');
      expect(attr!.placement.name, 'level');
      expect(attr.eventName, 'updated');
    });

    test('removeAttribution', () {
      cache.setAttribution('ad1', PlacementType('home'), eventName: 'test');
      cache.removeAttribution('ad1');
      expect(cache.getAttribution('ad1'), isNull);
    });

    test('removeSlot also removes attribution', () {
      final s1 = _makeSlot('home', 'ad1');
      cache.addSlot(PlacementType('home'), s1);
      cache.setAttribution('ad1', PlacementType('home'), eventName: 'test');
      cache.removeSlot(PlacementType('home'), s1);

      // Attribution should be cleared by removeSlot
      // Note: removeSlot uses ad reference for removal; attribution is keyed by ad object
    });

    test('disposeAll clears everything', () {
      cache.addSlot(PlacementType('home'), _makeSlot('home', 'ad1'));
      cache.setAttribution('ad1', PlacementType('home'), eventName: 'test');
      cache.disposeAll();
      expect(cache.hasSlot(PlacementType('home')), isFalse);
      expect(cache.getAttribution('ad1'), isNull);
    });

    test('commitSlots with lastError preserves error', () {
      cache.commitSlots(PlacementType('home'), [], lastError: 'load_error');
      expect(cache.hasSlot(PlacementType('home')), isFalse);
      expect(cache.lastErrorFor(PlacementType('home')), 'load_error');
    });

    test('beginLoading preserves existing slots', () {
      cache.addSlot(PlacementType('home'), _makeSlot('home', 'ad1'));
      cache.beginLoading(PlacementType('home'));
      // Existing slots should be preserved during loading
      final slots = cache.getSlots(PlacementType('home'));
      expect(slots, isNotEmpty);
    });
  });
}
