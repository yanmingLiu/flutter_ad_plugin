import 'package:flutter_ad_plugin/src/engine/ad_lifecycle_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdLifecycleManager', () {
    late AdLifecycleManager manager;

    setUp(() => manager = AdLifecycleManager());

    test('scheduleRefresh with valid minutes', () async {
      var fired = false;
      manager.scheduleRefresh('key1', 0, () => fired = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fired, isTrue);
    });

    test('hasRefresh returns true for active timer', () {
      manager.scheduleRefresh('key1', 60, () {});
      expect(manager.hasRefresh('key1'), isTrue);
    });

    test('scheduleRefresh cancels previous timer with same key', () async {
      var callCount = 0;
      manager.scheduleRefresh('key1', 0, () => callCount++);
      manager.scheduleRefresh('key1', 0, () => callCount++);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 1);
    });

    test('cancelRefresh removes timer', () {
      manager.scheduleRefresh('key1', 60, () {});
      manager.cancelRefresh('key1');
      expect(manager.hasRefresh('key1'), isFalse);
    });

    test('cancelRefresh is safe on non-existent key', () {
      manager.cancelRefresh('nonexistent');
    });

    test('dispose cancels all timers', () {
      manager.scheduleRefresh('key1', 0, () {});
      manager.scheduleRefresh('key2', 0, () {});
      manager.dispose();
      expect(manager.hasRefresh('key1'), isFalse);
      expect(manager.hasRefresh('key2'), isFalse);
    });

    test('default minutes is 40 when null', () {
      manager.scheduleRefresh('key1', null, () {});
      expect(manager.hasRefresh('key1'), isTrue);
    });
  });
}
