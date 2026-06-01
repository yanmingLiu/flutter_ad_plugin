import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdEventType', () {
    test('has all expected lifecycle events', () {
      expect(AdEventType.values, hasLength(9));
      expect(AdEventType.loadRequested, isNotNull);
      expect(AdEventType.loadSucceeded, isNotNull);
      expect(AdEventType.loadFailed, isNotNull);
      expect(AdEventType.show, isNotNull);
      expect(AdEventType.showSuccess, isNotNull);
      expect(AdEventType.showFail, isNotNull);
      expect(AdEventType.clicked, isNotNull);
      expect(AdEventType.income, isNotNull);
      expect(AdEventType.close, isNotNull);
    });
  });

  group('AdEvent', () {
    test('constructs with required fields only', () {
      final now = DateTime.now();
      final event = AdEvent(
        eventType: AdEventType.loadRequested,
        placement: const PlacementType('open'),
        adType: AdType.open,
        source: AdSource.admob,
        adUnitId: 'unit-1',
        timestamp: now,
        eventName: 'cold_start',
      );

      expect(event.eventType, AdEventType.loadRequested);
      expect(event.placement, const PlacementType('open'));
      expect(event.adType, AdType.open);
      expect(event.source, AdSource.admob);
      expect(event.adUnitId, 'unit-1');
      expect(event.timestamp, now);
      expect(event.eventName, 'cold_start');
      expect(event.placementLabel, isNull);
      expect(event.revenue, isNull);
      expect(event.currency, isNull);
      expect(event.errorCode, isNull);
      expect(event.errorReason, isNull);
      expect(event.network, isNull);
    });

    test('constructs with all fields', () {
      final now = DateTime.now();
      final event = AdEvent(
        eventType: AdEventType.showSuccess,
        placement: const PlacementType('home'),
        placementLabel: 'tab_home',
        adType: AdType.interstitial,
        source: AdSource.admob,
        adUnitId: 'unit-2',
        revenue: 1500.0,
        currency: 'USD',
        errorCode: null,
        errorReason: null,
        timestamp: now,
        eventName: 'first_show',
        network: 'AdMob',
      );

      expect(event.placementLabel, 'tab_home');
      expect(event.revenue, 1500.0);
      expect(event.currency, 'USD');
      expect(event.network, 'AdMob');
    });

    test('income event with revenue data', () {
      final event = AdEvent(
        eventType: AdEventType.income,
        placement: const PlacementType('home'),
        adType: AdType.interstitial,
        source: AdSource.admob,
        adUnitId: 'unit-3',
        revenue: 2500,
        currency: 'USD',
        timestamp: DateTime.now(),
        eventName: 'hot_open',
        network: 'AdMob',
      );

      expect(event.eventType, AdEventType.income);
      expect(event.revenue, 2500);
      expect(event.currency, 'USD');
      expect(event.network, 'AdMob');
    });

    test('loadFailed event with error info', () {
      final event = AdEvent(
        eventType: AdEventType.loadFailed,
        placement: const PlacementType('level_h'),
        adType: AdType.interstitial,
        source: AdSource.admob,
        adUnitId: 'unit-fail',
        errorCode: 3,
        errorReason: 'No fill',
        timestamp: DateTime.now(),
        eventName: 'level_load',
      );

      expect(event.errorCode, 3);
      expect(event.errorReason, 'No fill');
    });
  });

  group('AdEvent.toJson', () {
    test('basic event serializes correctly', () {
      final now = DateTime.utc(2026, 1, 15, 10, 30, 0);
      final event = AdEvent(
        eventType: AdEventType.loadSucceeded,
        placement: const PlacementType('open'),
        adType: AdType.open,
        source: AdSource.admob,
        adUnitId: 'unit-1',
        timestamp: now,
        eventName: 'cold_load',
      );

      final json = event.toJson();
      expect(json['event_type'], 'loadSucceeded');
      expect(json['placement'], 'open');
      expect(json['ad_type'], 'open');
      expect(json['ad_source'], 'admob');
      expect(json['ad_unit_id'], 'unit-1');
      expect(json['timestamp'], '2026-01-15T10:30:00.000Z');
      expect(json['event_name'], 'cold_load');
      expect(json['revenue'], isNull);
      expect(json['currency'], isNull);
      expect(json['error_code'], isNull);
      expect(json['error_reason'], isNull);
      expect(json['network'], isNull);
    });

    test('full event serializes all fields', () {
      final now = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final event = AdEvent(
        eventType: AdEventType.income,
        placement: const PlacementType('home'),
        placementLabel: 'inbox_top',
        adType: AdType.interstitial,
        source: AdSource.admob,
        adUnitId: 'unit-income',
        revenue: 3200.0,
        currency: 'USD',
        errorCode: null,
        errorReason: null,
        timestamp: now,
        eventName: 'hot_show',
        network: 'AdMob',
      );

      final json = event.toJson();
      expect(json['event_type'], 'income');
      expect(json['placement'], 'home');
      expect(json['placement_label'], 'inbox_top');
      expect(json['ad_type'], 'interstitial');
      expect(json['ad_source'], 'admob');
      expect(json['ad_unit_id'], 'unit-income');
      expect(json['revenue'], 3200.0);
      expect(json['currency'], 'USD');
      expect(json['timestamp'], '2026-06-01T12:00:00.000Z');
      expect(json['event_name'], 'hot_show');
      expect(json['network'], 'AdMob');
    });

    test('close event serializes correctly', () {
      final now = DateTime.utc(2026, 3, 1, 0, 0, 0);
      final event = AdEvent(
        eventType: AdEventType.close,
        placement: const PlacementType('open'),
        adType: AdType.open,
        source: AdSource.admob,
        adUnitId: 'unit-close',
        timestamp: now,
        eventName: 'dismiss_cold',
        network: 'AdMob',
      );

      final json = event.toJson();
      expect(json['event_type'], 'close');
      expect(json['network'], 'AdMob');
    });

    test('show event serializes correctly', () {
      final now = DateTime.utc(2026, 5, 1, 8, 0, 0);
      final event = AdEvent(
        eventType: AdEventType.show,
        placement: const PlacementType('interstitial'),
        placementLabel: 'inbox',
        adType: AdType.interstitial,
        source: AdSource.admob,
        adUnitId: 'unit-show',
        timestamp: now,
        eventName: 'first_show',
      );

      final json = event.toJson();
      expect(json['event_type'], 'show');
      expect(json['placement'], 'interstitial');
      expect(json['placement_label'], 'inbox');
      expect(json['ad_type'], 'interstitial');
      expect(json['ad_unit_id'], 'unit-show');
      expect(json['timestamp'], '2026-05-01T08:00:00.000Z');
      expect(json['event_name'], 'first_show');
    });

    test('showFail event with errorReason serializes correctly', () {
      final now = DateTime.utc(2026, 5, 1, 9, 0, 0);
      final event = AdEvent(
        eventType: AdEventType.showFail,
        placement: const PlacementType('open'),
        adType: AdType.open,
        source: AdSource.admob,
        adUnitId: 'unit-fail',
        errorReason: 'guard_blocked: fullscreenShowing',
        timestamp: now,
        eventName: 'cold_show',
      );

      final json = event.toJson();
      expect(json['event_type'], 'showFail');
      expect(json['placement'], 'open');
      expect(json['error_reason'], 'guard_blocked: fullscreenShowing');
      expect(json['event_name'], 'cold_show');
    });
  });

  group('DefaultAdEventReporter', () {
    test('report does not throw', () async {
      final reporter = DefaultAdEventReporter();
      final event = AdEvent(
        eventType: AdEventType.loadRequested,
        placement: const PlacementType('test'),
        adType: AdType.native,
        source: AdSource.admob,
        adUnitId: 'test-unit',
        timestamp: DateTime.now(),
        eventName: 'test_event',
      );
      await reporter.report(event);
      // Just verifying it doesn't throw
    });
  });

  group('AdNotReadyEvent', () {
    test('all fields are stored', () {
      const event = AdNotReadyEvent(
        requestedPlacement: PlacementType('interstitial'),
        showPlacement: PlacementType('open'),
        placementLabel: 'start_screen',
        eventName: 'cold_start',
        message: 'Ad not ready yet, please try again',
      );
      expect(event.requestedPlacement, const PlacementType('interstitial'));
      expect(event.showPlacement, const PlacementType('open'));
      expect(event.placementLabel, 'start_screen');
      expect(event.eventName, 'cold_start');
      expect(event.message, 'Ad not ready yet, please try again');
    });
  });
}
