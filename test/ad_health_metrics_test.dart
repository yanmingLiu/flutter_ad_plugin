import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/reporting/ad_health_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdHealthMetrics', () {
    late AdHealthMetrics metrics;
    const placement = PlacementType('home');

    setUp(() => metrics = AdHealthMetrics());

    test('returns null snapshot when no data', () {
      expect(metrics.snapshot(placement), isNull);
    });

    test('tracks load success and calculates fill rate', () {
      metrics.recordLoadAttempt(placement);
      metrics.recordLoadAttempt(placement);
      metrics.recordLoadSuccess(placement, Duration(seconds: 1));
      metrics.recordLoadFailure(placement);

      final snap = metrics.snapshot(placement);
      expect(snap, isNotNull);
      expect(snap!.loadAttempts, 2);
      expect(snap.loadSuccesses, 1);
      expect(snap.loadFailures, 1);
      expect(snap.fillRate, closeTo(0.5, 0.01));
    });

    test('calculates avg load latency', () {
      metrics.recordLoadAttempt(placement);
      metrics.recordLoadSuccess(placement, Duration(seconds: 1));
      metrics.recordLoadAttempt(placement);
      metrics.recordLoadSuccess(placement, Duration(seconds: 3));

      final snap = metrics.snapshot(placement)!;
      expect(snap.totalLoadLatency, Duration(seconds: 4));
      expect(snap.avgLoadLatency, Duration(seconds: 2));
    });

    test('tracks show attempts', () {
      metrics.recordShowAttempt(placement);
      metrics.recordShowSuccess(placement);
      metrics.recordShowAttempt(placement);
      metrics.recordShowFailure(placement);

      final snap = metrics.snapshot(placement)!;
      expect(snap.showAttempts, 2);
      expect(snap.showSuccesses, 1);
      expect(snap.showFailures, 1);
      expect(snap.showRate, closeTo(0.5, 0.01));
    });

    test('fillRate returns 0 when no attempts', () {
      expect(metrics.snapshot(placement), isNull);
    });

    test('reset clears all data', () {
      metrics.recordLoadAttempt(placement);
      metrics.recordLoadSuccess(placement, Duration(seconds: 1));
      metrics.reset();

      expect(metrics.snapshot(placement), isNull);
    });

    test('multiple placements tracked independently', () {
      const p1 = PlacementType('home');
      const p2 = PlacementType('level');

      metrics.recordLoadAttempt(p1);
      metrics.recordLoadSuccess(p1, Duration(seconds: 1));
      metrics.recordLoadAttempt(p2);
      metrics.recordLoadFailure(p2);

      final snap1 = metrics.snapshot(p1)!;
      final snap2 = metrics.snapshot(p2)!;

      expect(snap1.loadAttempts, 1);
      expect(snap1.loadSuccesses, 1);
      expect(snap2.loadAttempts, 1);
      expect(snap2.loadFailures, 1);
    });

    test('allSnapshots returns all tracked placements', () {
      metrics.recordLoadAttempt(PlacementType('home'));
      metrics.recordLoadAttempt(PlacementType('level'));

      final all = metrics.allSnapshots();
      expect(all, hasLength(2));
    });
  });
}
