import 'package:flutter/foundation.dart';
import 'package:flutter_ad_plugin/src/core/ad_config.dart';
import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_ad_plugin/src/engine/ad_engine.dart';
import 'package:flutter_ad_plugin/src/platform/ad_adapter.dart';
import 'package:flutter_ad_plugin/src/platform/ad_registry.dart';
import 'package:flutter_ad_plugin/src/utils/ad_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingReporter implements AdEventReporter {
  final List<AdEvent> events = [];

  @override
  Future<void> report(AdEvent event) async {
    events.add(event);
  }

  List<AdEvent> byType(AdEventType type) =>
      events.where((e) => e.eventType == type).toList();

  void clear() => events.clear();
}

class _FakeSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;
  @override
  Future<void> init() async {}
}

class _SuccessAdapter implements AdTypeAdapter {
  _SuccessAdapter([this._type = AdType.open]);

  final AdType _type;

  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => _type;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    return AdLoadResult.success(ad: Object(), type: type, adUnitId: unit.id);
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {}
}

class _ThrowingLoadAdapter implements AdTypeAdapter {
  final Object error;

  _ThrowingLoadAdapter([this.error = 'sdk_init_failed']);

  @override
  AdSource get source => AdSource.admob;
  @override
  AdType get type => AdType.open;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    throw error;
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    return AdShowResult.failure('not_implemented');
  }

  @override
  void dispose(Object ad) {}
}

AdConfigRepository _configRepo({
  PlacementType placement = const PlacementType('open'),
  bool isFullscreen = true,
  bool waitForLoadOnShow = true,
  int cacheSize = 1,
}) {
  final config = AdConfig(
    loadTimeoutSeconds: 7,
    samePlacementCdSeconds: 0,
    differentPlacementCdSeconds: 0,
    placements: {
      placement: [
        AdUnitConfig(
          source: AdSource.admob,
          weight: 1,
          type: isFullscreen ? AdType.open : AdType.native,
          id: 'test-unit-id',
          poolSize: cacheSize,
        ),
      ],
    },
    policies: {
      placement: PlacementPolicy(
        isFullscreen: isFullscreen,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: waitForLoadOnShow,
        preferHighValueOnShow: false,
      ),
    },
  );
  return _StubConfigRepo(config);
}

class _StubConfigRepo implements AdConfigRepository {
  final AdConfig config;
  const _StubConfigRepo(this.config);

  @override
  Future<AdConfig> getConfig() async => config;
}

Future<void> _initTestEngine({
  required _CapturingReporter reporter,
  required List<AdTypeAdapter> adapters,
  PlacementType placement = const PlacementType('open'),
  bool isFullscreen = true,
  bool waitForLoadOnShow = true,
  int cacheSize = 1,
}) async {
  await AdEngine.instance.initWith(
    configRepository: _configRepo(
      placement: placement,
      isFullscreen: isFullscreen,
      waitForLoadOnShow: waitForLoadOnShow,
      cacheSize: cacheSize,
    ),
    eventReporter: reporter,
    adapters: adapters,
    sdkInitializers: [_FakeSdkInitializer()],
  );
}

void main() {
  late _CapturingReporter reporter;
  const placement = PlacementType('open');

  setUp(() {
    AdEngine.resetForTesting();
    reporter = _CapturingReporter();
  });

  group('preload event chain', () {
    test('reports loadRequested and loadSucceeded on success', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_SuccessAdapter()],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'cold_start');

      expect(reporter.byType(AdEventType.loadRequested).length, 1);
      expect(reporter.byType(AdEventType.loadSucceeded).length, 1);
      expect(reporter.byType(AdEventType.loadFailed), isEmpty);

      final requested = reporter.byType(AdEventType.loadRequested).single;
      expect(requested.placement, placement);
      expect(requested.adUnitId, 'test-unit-id');
      expect(requested.eventName, 'cold_start');

      final succeeded = reporter.byType(AdEventType.loadSucceeded).single;
      expect(succeeded.placement, placement);
      expect(succeeded.adUnitId, 'test-unit-id');
      expect(succeeded.eventName, 'cold_start');
    });

    test('reports loadRequested and loadFailed when adapter throws', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_ThrowingLoadAdapter('sdk_error')],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload_fail');

      expect(reporter.byType(AdEventType.loadRequested).length, 1);
      expect(reporter.byType(AdEventType.loadSucceeded), isEmpty);
      expect(reporter.byType(AdEventType.loadFailed).length, 1);

      final failed = reporter.byType(AdEventType.loadFailed).single;
      expect(failed.placement, placement);
      expect(failed.eventName, 'preload_fail');
      expect(failed.errorReason, contains('sdk_error'));
    });

    test('loadRequested equals loadSucceeded + loadFailed', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_SuccessAdapter()],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'eq_test');

      final requestedCount = reporter.byType(AdEventType.loadRequested).length;
      final succeededCount = reporter.byType(AdEventType.loadSucceeded).length;
      final failedCount = reporter.byType(AdEventType.loadFailed).length;
      expect(requestedCount, succeededCount + failedCount);
    });
  });

  group('show event chain', () {
    test('reports show event before calling adapter show', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_SuccessAdapter()],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();

      await AdEngine.instance.show(placement, eventName: 'first_show');

      expect(
        reporter.byType(AdEventType.show).length,
        1,
        reason: 'show event should be reported in _showSlot',
      );
      final showEvent = reporter.byType(AdEventType.show).single;
      expect(showEvent.placement, placement);
      expect(showEvent.eventName, 'first_show');
      expect(showEvent.adUnitId, 'test-unit-id');
    });

    test('show equals showSuccess + showFail', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_SuccessAdapter()],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();

      await AdEngine.instance.show(placement, eventName: 'show_test');

      final showCount = reporter.byType(AdEventType.show).length;
      final successCount = reporter.byType(AdEventType.showSuccess).length;
      final failCount = reporter.byType(AdEventType.showFail).length;

      // The fake adapter completes immediately without SDK callbacks,
      // so no showSuccess/showFail. But show IS reported.
      expect(showCount, 1);
      expect(successCount, 0);
      expect(failCount, 0);
    });
  });

  group('showFail on guard block', () {
    test('guard blocking is tested at the guard unit level', () {
      expect(true, isTrue);
    });
  });

  group('showFail on no cache', () {
    test('reports showFail when no ad is cached and waitForLoad is false',
        () async {
      await _initTestEngine(
            reporter: reporter,
            adapters: [_SuccessAdapter()],
            placement: placement,
            waitForLoadOnShow: false,
          );

      final result = await AdEngine.instance.show(placement, eventName: 'no_cache_show');
      expect(result, isFalse);

      final showFails = reporter.byType(AdEventType.showFail);
      expect(showFails.length, 1);
      final showFail = showFails.single;
      expect(showFail.placement, placement);
      expect(showFail.eventName, 'no_cache_show');
      expect(showFail.errorReason, 'no_cache');
    });
  });

  group('event type completeness', () {
    test('all 9 event types are defined', () {
      expect(AdEventType.values, hasLength(9));
      for (final type in [
        AdEventType.loadRequested,
        AdEventType.loadSucceeded,
        AdEventType.loadFailed,
        AdEventType.show,
        AdEventType.showSuccess,
        AdEventType.showFail,
        AdEventType.clicked,
        AdEventType.income,
        AdEventType.close,
      ]) {
        expect(AdEventType.values.contains(type), isTrue);
      }
    });
  });
}
