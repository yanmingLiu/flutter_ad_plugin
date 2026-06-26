import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/engine/ad_event_mapper.dart';
import 'package:flutter_ad_plugin/src/platform/ad_callback.dart';
import 'package:flutter_ad_plugin/src/utils/ad_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdEventMapper', () {
    late AdEventMapper mapper;

    setUp(() => mapper = AdEventMapper());

    const placement = PlacementType('home');
    const adType = AdType.interstitial;
    const source = AdSource.admob;
    const adUnitId = 'ca-app-pub-test';
    const eventName = 'cold_start';

    test('maps AdImpressionCallback to showSuccess', () {
      final cb = AdImpressionCallback('ad_obj', 'network1');
      final event = mapper.map(
        cb,
        placement: placement,
        eventName: eventName,
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.eventType, AdEventType.showSuccess);
      expect(event.placement, placement);
      expect(event.network, 'network1');
      expect(event.eventName, eventName);
    });

    test('maps AdPaidCallback to income', () {
      final cb = AdPaidCallback('ad_obj', 1000000, 'USD', 'network1');
      final event = mapper.map(
        cb,
        placement: placement,
        eventName: eventName,
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.eventType, AdEventType.income);
      expect(event.revenue, 1000000);
      expect(event.currency, 'USD');
      expect(event.network, 'network1');
    });

    test('maps AdClickedCallback to clicked', () {
      final cb = AdClickedCallback('ad_obj', 'network1');
      final event = mapper.map(
        cb,
        placement: placement,
        eventName: eventName,
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.eventType, AdEventType.clicked);
    });

    test('maps AdClosedCallback to close', () {
      final cb = AdClosedCallback('ad_obj', 'network1');
      final event = mapper.map(
        cb,
        placement: placement,
        eventName: eventName,
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.eventType, AdEventType.close);
    });

    test('maps AdShowedCallback to showSuccess', () {
      final cb = AdShowedCallback('ad_obj', 'network1');
      final event = mapper.map(
        cb,
        placement: placement,
        eventName: eventName,
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.eventType, AdEventType.showSuccess);
    });

    test('maps AdShowFailedCallback to showFail', () {
      final cb = AdShowFailedCallback('ad_obj', 3, 'No fill', 'network1');
      final event = mapper.map(
        cb,
        placement: placement,
        eventName: eventName,
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.eventType, AdEventType.showFail);
      expect(event.errorCode, 3);
      expect(event.errorReason, 'No fill');
      expect(event.network, 'network1');
    });

    test('maps all placementLabel and eventName fields', () {
      final cb = AdShowedCallback('ad_obj', null);
      final event = mapper.map(
        cb,
        placement: placement,
        placementLabel: 'inbox_top',
        eventName: 'custom_event',
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.placementLabel, 'inbox_top');
      expect(event.eventName, 'custom_event');
    });

    test('timestamp is set on all events', () {
      final cb = AdShowedCallback('ad_obj', null);
      final event = mapper.map(
        cb,
        placement: placement,
        eventName: eventName,
        adType: adType,
        source: source,
        adUnitId: adUnitId,
      );
      expect(event.timestamp, isNotNull);
    });
  });
}
