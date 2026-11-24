import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ad_core/flutter_ad_core.dart';
import 'package:flutter_ad_core/platform.dart';

class _Platform extends AdPlatform {
  _Platform(this.source, this.initialize);
  @override
  final AdSource source;
  final Future<void> Function() initialize;
  @override
  Future<void> init() => initialize();
  @override
  List<FullscreenAdAdapter> get fullscreenAdapters => [];
  @override
  List<InlineAdAdapter> get inlineAdapters => [];
}

void main() {
  test(
    'reports pending and successful initialization with immutable snapshots',
    () async {
      final gate = Completer<void>();
      final ads = AdPlugin(
        config: {},
        platforms: [_Platform(AdSource.admob, () => gate.future)],
      );
      expect(
        ads.initializationStatus(AdSource.admob)?.state,
        AdInitializationState.notStarted,
      );
      expect(ads.initializationStatus(AdSource.max), isNull);
      expect(ads.initializationStatus(null), isNull);
      final before = ads.initializationStatuses;
      final pending = ads.init();
      expect(
        ads.initializationStatus(AdSource.admob)?.state,
        AdInitializationState.initializing,
      );
      gate.complete();
      await pending;
      expect(ads.initializationStatus(AdSource.admob)?.isSuccess, isTrue);
      expect(before[AdSource.admob]?.state, AdInitializationState.notStarted);
      expect(() => before.clear(), throwsUnsupportedError);
      await ads.dispose();
    },
  );

  test(
    'preserves failure details, skipped platforms and retry results',
    () async {
      var fail = true;
      final error = StateError('SDK failure');
      final ads = AdPlugin(
        config: {},
        platforms: [
          _Platform(AdSource.admob, () async {}),
          _Platform(AdSource.topon, () async {
            if (fail) throw error;
          }),
          _Platform(AdSource.max, () async {}),
        ],
      );
      await expectLater(ads.init(), throwsA(same(error)));
      expect(ads.isInitialized, isFalse);
      expect(ads.initializationStatus(AdSource.admob)?.isSuccess, isTrue);
      expect(
        ads.initializationStatus(AdSource.topon)?.state,
        AdInitializationState.failed,
      );
      expect(ads.initializationStatus(AdSource.topon)?.error, same(error));
      expect(
        ads.initializationStatus(AdSource.max)?.state,
        AdInitializationState.notStarted,
      );
      fail = false;
      await ads.init();
      expect(
        ads.initializationStatuses.values.every((status) => status.isSuccess),
        isTrue,
      );
      expect(ads.initializationStatus(AdSource.topon)?.error, isNull);
      await ads.dispose();
    },
  );
}
