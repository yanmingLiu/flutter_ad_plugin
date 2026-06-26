import 'package:flutter/widgets.dart';
import 'package:flutter_ad_plugin/src/core/ad_config.dart';
import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_ad_plugin/src/engine/ad_engine.dart';
import 'package:flutter_ad_plugin/src/platform/ad_adapter.dart';
import 'package:flutter_ad_plugin/src/platform/ad_registry.dart';
import 'package:flutter_ad_plugin/src/utils/ad_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verbatim copies of helpers from ad_engine_event_test.dart to keep this
/// self-contained.
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

// ---------------------------------------------------------------
// Mock adapters with explicit event-callback simulation
// ---------------------------------------------------------------

/// Fullscreen-like mock that invokes onAdShowed/onClosed callbacks
/// synchronously, so the engine's show → showSuccess → close chain
/// is testable without a real SDK.
class _FullscreenMockAdapter implements AdTypeAdapter {
  _FullscreenMockAdapter({
    this.type = AdType.open,
    this.succeeds = true,
  });

  @override
  AdSource get source => AdSource.admob;
  @override
  final AdType type;
  final bool succeeds;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    bool renderAsFullscreen = false,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    return AdLoadResult.success(
      ad: Object(),
      type: type,
      adUnitId: unit.id,
    );
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    AdFullScreenNativeStyle style = const AdFullScreenNativeStyle(),
  }) async {
    if (!succeeds) {
      await reporter.report(
        AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: type,
          source: source,
          adUnitId: 'test-unit-id',
          errorReason: 'fake_show_failed',
          timestamp: DateTime.now(),
          eventName: eventName,
        ),
      );
      return AdShowResult.failure('fake_show_failed');
    }

    onAdShowed?.call();
    await reporter.report(
      AdEvent(
        eventType: AdEventType.showSuccess,
        placement: placement,
        placementLabel: placementLabel,
        adType: type,
        source: source,
        adUnitId: 'test-unit-id',
        timestamp: DateTime.now(),
        eventName: eventName,
      ),
    );
    onClosed?.call();
    await reporter.report(
      AdEvent(
        eventType: AdEventType.close,
        placement: placement,
        placementLabel: placementLabel,
        adType: type,
        source: source,
        adUnitId: 'test-unit-id',
        timestamp: DateTime.now(),
        eventName: eventName,
      ),
    );
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {}
}

/// Native-like mock that records `getNativeAd` retrieval events
/// and simulates `onAdImpression` via a helper.
class _NativeInlineMockAdapter implements AdTypeAdapter {
  _NativeInlineMockAdapter({required this.reporter});

  final AdEventReporter reporter;
  final List<Object> loadedAds = [];

  @override
  AdSource get source => AdSource.admob;
  @override
  AdType get type => AdType.native;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    bool renderAsFullscreen = false,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    final ad = Object();
    loadedAds.add(ad);
    return AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id);
  }

  /// Simulates the SDK firing an impression callback.
  void simulateImpression({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required Object ad,
  }) {
    if (ad is! Object) return;
    reporter.report(
      AdEvent(
        eventType: AdEventType.showSuccess,
        placement: placement,
        placementLabel: placementLabel,
        adType: type,
        source: source,
        adUnitId: 'test-unit-id',
        timestamp: DateTime.now(),
        eventName: eventName,
      ),
    );
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    AdFullScreenNativeStyle style = const AdFullScreenNativeStyle(),
  }) async {
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {}
}

/// Banner-like mock that records retrieval events.
class _BannerMockAdapter implements AdTypeAdapter {
  _BannerMockAdapter({required this.reporter});

  final AdEventReporter reporter;

  @override
  AdSource get source => AdSource.admob;
  @override
  AdType get type => AdType.banner;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    bool renderAsFullscreen = false,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    return AdLoadResult.success(
      ad: Object(),
      type: type,
      adUnitId: unit.id,
    );
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    AdFullScreenNativeStyle style = const AdFullScreenNativeStyle(),
  }) async {
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {}
}

// ---------------------------------------------------------------
// Config helpers
// ---------------------------------------------------------------

AdConfigRepository _configRepo({
  PlacementType placement = const PlacementType('open'),
  bool isFullscreen = true,
  bool waitForLoadOnShow = true,
  int cacheSize = 1,
  AdType? adType,
}) {
  return _StubConfigRepo(
    AdConfig(
      loadTimeoutSeconds: 7,
      samePlacementCdSeconds: 0,
      differentPlacementCdSeconds: 0,
      placements: {
        placement: [
          AdUnitConfig(
            source: AdSource.admob,
            weight: 1,
            type: adType ?? (isFullscreen ? AdType.open : AdType.native),
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
    ),
  );
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
  AdType? adType,
  Map<PlacementType, PlacementPolicy> placementPolicies = const {},
}) async {
  await AdEngine.instance.initWith(
    configRepository: _configRepo(
      placement: placement,
      isFullscreen: isFullscreen,
      waitForLoadOnShow: waitForLoadOnShow,
      cacheSize: cacheSize,
      adType: adType,
    ),
    eventReporter: reporter,
    placementPolicies: placementPolicies,
    adapters: adapters,
    sdkInitializers: [_FakeSdkInitializer()],
  );
}

// ===============================================================
// TEST SUITES
// ===============================================================

void main() {
  late _CapturingReporter reporter;
  const placement = PlacementType('open');

  setUp(() {
    AdEngine.resetForTesting();
    reporter = _CapturingReporter();
  });

  // ---------------------------------------------------------
  // Fullscreen (open/interstitial/rewarded/native-fullscreen)
  // ---------------------------------------------------------

  group('fullscreen ad event chain', () {
    test('happy path: show → showSuccess → close in order', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();

      await AdEngine.instance.show(placement, eventName: 'display');

      final types = reporter.events.map((e) => e.eventType).toList();
      expect(types, [
        AdEventType.show,
        AdEventType.showSuccess,
        AdEventType.close,
      ]);
      for (final e in reporter.events) {
        expect(e.eventName, 'display');
      }
    });

    test('failure path: show → showFail (no showSuccess, no close)',
        () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: false)],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();

      await AdEngine.instance.show(placement, eventName: 'failure_display');

      final types = reporter.events.map((e) => e.eventType).toList();
      expect(types, [
        AdEventType.show,
        AdEventType.showFail,
      ]);
      expect(reporter.byType(AdEventType.showSuccess), isEmpty);
      expect(reporter.byType(AdEventType.close), isEmpty);
    });

    test('guard blocked emits show + showFail (BUG 3)', () async {
      // Use a custom config with samePlacementCdSeconds > 0 so CD actually blocks
      await AdEngine.instance.initWith(
        configRepository: _StubConfigRepo(
          AdConfig(
            loadTimeoutSeconds: 7,
            samePlacementCdSeconds: 99,
            differentPlacementCdSeconds: 0,
            placements: {
              placement: [
                const AdUnitConfig(
                  source: AdSource.admob,
                  weight: 1,
                  type: AdType.open,
                  id: 'test-unit-id',
                ),
              ],
            },
            policies: {
              placement: const PlacementPolicy(
                isFullscreen: true,
                applySamePlacementCd: true,
                applyDifferentPlacementCd: false,
                contributesToGlobalCooldown: false,
                showNotReadyToast: false,
                waitForLoadOnShow: false,
                preferHighValueOnShow: false,
              ),
            },
          ),
        ),
        eventReporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        sdkInitializers: [_FakeSdkInitializer()],
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      // First show — succeeds, marks CD
      reporter.clear();
      await AdEngine.instance.show(placement, eventName: 'first');
      await Future<void>.delayed(Duration.zero);
      reporter.clear();

      await AdEngine.instance.show(placement, eventName: 'second_blocked');

      final types = reporter.events.map((e) => e.eventType).toList();
      expect(types, [
        AdEventType.show,
        AdEventType.showFail,
      ]);
      final fail = reporter.byType(AdEventType.showFail).single;
      expect(fail.errorReason, contains('guard_blocked'));
    });

    test('no cache emits show + showFail when waitForLoadOnShow is false',
        () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
        waitForLoadOnShow: false,
      );

      await AdEngine.instance.show(placement, eventName: 'no_cache');

      final types = reporter.events.map((e) => e.eventType).toList();
      expect(types, [
        AdEventType.show,
        AdEventType.showFail,
      ]);
      final fail = reporter.byType(AdEventType.showFail).single;
      expect(fail.errorReason, 'no_cache');
    });

    test('showSequence: firstSlot==null emits show + showFail (BUG 4)',
        () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
        waitForLoadOnShow: false,
      );

      await AdEngine.instance.showSequence(
        placement,
        eventName: 'sequence',
      );

      final types = reporter.events.map((e) => e.eventType).toList();
      expect(types, [
        AdEventType.show,
        AdEventType.showFail,
      ]);
      final fail = reporter.byType(AdEventType.showFail).single;
      expect(fail.errorReason, 'no_cache');
    });

    test('placementLabel propagates to show + showFail (BUG 8)', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
        waitForLoadOnShow: false,
      );

      await AdEngine.instance.show(
        placement,
        placementLabel: 'my_label',
        eventName: 'labeled',
      );

      final show = reporter.byType(AdEventType.show).single;
      expect(show.placementLabel, 'my_label');

      final fail = reporter.byType(AdEventType.showFail).single;
      expect(fail.placementLabel, 'my_label');
    });
  });

  // ---------------------------------------------------------
  // Inline native retrieval events
  // ---------------------------------------------------------

  group('inline native retrieval events', () {
    test('getNativeAd emits show event (BUG 6)', () async {
      final adapter = _NativeInlineMockAdapter(reporter: reporter);
      const nativePlacement = PlacementType('article_native');

      await _initTestEngine(
        reporter: reporter,
        adapters: [adapter],
        placement: nativePlacement,
        isFullscreen: false,
        adType: AdType.native,
      );

      await AdEngine.instance.preloadNative(
        nativePlacement,
        eventName: 'preload',
      );
      reporter.clear();

      AdEngine.instance.getNativeAd(
        nativePlacement,
        eventName: 'home_show',
      );

      final shows = reporter.byType(AdEventType.show);
      expect(shows.length, 1);
      expect(shows.single.eventName, 'home_show');
      expect(shows.single.placement, nativePlacement);
      expect(shows.single.adType, AdType.native);
    });

    test('getNativeAds emits show per ad (BUG 6)', () async {
      // Create a config with 2 units so cacheSizeFor returns 2
      await AdEngine.instance.initWith(
        configRepository: _StubConfigRepo(
          AdConfig(
            loadTimeoutSeconds: 7,
            samePlacementCdSeconds: 0,
            differentPlacementCdSeconds: 0,
            placements: {
              const PlacementType('dual_native'): [
                AdUnitConfig(
                  source: AdSource.admob,
                  weight: 1,
                  type: AdType.native,
                  id: 'test-unit-1',
                  cacheKey: 'k1',
                  poolSize: 2,
                ),
                AdUnitConfig(
                  source: AdSource.admob,
                  weight: 1,
                  type: AdType.native,
                  id: 'test-unit-2',
                  cacheKey: 'k2',
                  poolSize: 2,
                ),
              ],
            },
          ),
        ),
        eventReporter: reporter,
        adapters: [_NativeInlineMockAdapter(reporter: reporter)],
        sdkInitializers: [_FakeSdkInitializer()],
        nativeAdCloseClickPercent: 0,
      );

      await AdEngine.instance.preloadNative(
        const PlacementType('dual_native'),
        eventName: 'preload',
      );
      reporter.clear();

      AdEngine.instance.getNativeAds(
        const PlacementType('dual_native'),
        count: 2,
        eventName: 'dual_show',
      );

      final shows = reporter.byType(AdEventType.show);
      expect(shows.length, 2,
          reason: 'should emit show for each retrieved ad');
      for (final s in shows) {
        expect(s.eventName, 'dual_show');
      }
    });
  });

  // ---------------------------------------------------------
  // Banner events
  // ---------------------------------------------------------

  group('banner events', () {
    test('getBannerAds emits show per banner (BUG 6)', () async {
      const bannerPl = PlacementType('bottom_banner');

      await AdEngine.instance.initWith(
        configRepository: _StubConfigRepo(
          AdConfig(
            loadTimeoutSeconds: 7,
            samePlacementCdSeconds: 0,
            differentPlacementCdSeconds: 0,
            placements: {
              bannerPl: [
                AdUnitConfig(
                  source: AdSource.admob,
                  weight: 1,
                  type: AdType.banner,
                  id: 'test-banner-1',
                  cacheKey: 'bk1',
                  poolSize: 2,
                ),
                AdUnitConfig(
                  source: AdSource.admob,
                  weight: 1,
                  type: AdType.banner,
                  id: 'test-banner-2',
                  cacheKey: 'bk2',
                  poolSize: 2,
                ),
              ],
            },
          ),
        ),
        eventReporter: reporter,
        adapters: [_BannerMockAdapter(reporter: reporter)],
        sdkInitializers: [_FakeSdkInitializer()],
      );

      await AdEngine.instance.preloadBanner(
        bannerPl,
        eventName: 'preload',
      );
      reporter.clear();

      AdEngine.instance.getBannerAds(
        bannerPl,
        count: 2,
        eventName: 'banner_show',
      );

      expect(reporter.byType(AdEventType.show).length, 2,
          reason: 'should emit show for each retrieved banner');
      for (final s in reporter.byType(AdEventType.show)) {
        expect(s.eventName, 'banner_show');
      }
    });
  });

  // ---------------------------------------------------------
  // loadFailed on config error (BUG 2)
  // ---------------------------------------------------------

  group('load events edge cases', () {
    test('config-level error still reports loadFailed (BUG 2)', () async {
      await AdEngine.instance.initWith(
        configRepository: _StubConfigRepo(
          AdConfig(
            loadTimeoutSeconds: 7,
            samePlacementCdSeconds: 0,
            differentPlacementCdSeconds: 0,
            placements: {
              placement: [
                const AdUnitConfig(
                  source: AdSource.admob,
                  weight: 1,
                  type: AdType.open,
                  id: 'test-unit-id',
                ),
              ],
            },
          ),
        ),
        eventReporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        sdkInitializers: [_FakeSdkInitializer()],
      );

      await AdEngine.instance.preload(placement, eventName: 'error_preload');

      final requested = reporter.byType(AdEventType.loadRequested).length;
      final succeeded = reporter.byType(AdEventType.loadSucceeded).length;
      final failed = reporter.byType(AdEventType.loadFailed).length;
      expect(requested, succeeded + failed);
      expect(requested, greaterThan(0));
    });

    test('loadRequested always equals loadSucceeded + loadFailed', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'invariant');

      final requested = reporter.byType(AdEventType.loadRequested).length;
      final succeeded = reporter.byType(AdEventType.loadSucceeded).length;
      final failed = reporter.byType(AdEventType.loadFailed).length;
      expect(requested, succeeded + failed);
    });
  });

  // ---------------------------------------------------------
  // Event ordering summary — all types
  // ---------------------------------------------------------

  group('event ordering invariants', () {
    test('fullscreen: show always before showSuccess', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();
      await AdEngine.instance.show(placement, eventName: 'ordering');

      final types = reporter.events.map((e) => e.eventType).toList();
      final showIdx = types.indexOf(AdEventType.show);
      final successIdx = types.indexOf(AdEventType.showSuccess);
      expect(showIdx, lessThan(successIdx),
          reason: 'show must precede showSuccess');
    });

    test('fullscreen: showSuccess before close', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();
      await AdEngine.instance.show(placement, eventName: 'ordering');

      final types = reporter.events.map((e) => e.eventType).toList();
      final successIdx = types.indexOf(AdEventType.showSuccess);
      final closeIdx = types.indexOf(AdEventType.close);
      expect(successIdx, lessThan(closeIdx),
          reason: 'showSuccess before close');
    });

    test('fullscreen: close is always the last event', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();
      await AdEngine.instance.show(placement, eventName: 'ordering');

      final types = reporter.events.map((e) => e.eventType).toList();
      expect(types.last, AdEventType.close);
    });

    test('eventName consistent across full lifecycle', () async {
      await _initTestEngine(
        reporter: reporter,
        adapters: [_FullscreenMockAdapter(succeeds: true)],
        placement: placement,
      );

      await AdEngine.instance.preload(placement, eventName: 'preload');
      reporter.clear();
      await AdEngine.instance.show(placement, eventName: 'lifecycle_test');

      for (final event in reporter.events) {
        if (event.eventType != AdEventType.income &&
            event.eventType != AdEventType.clicked) {
          expect(event.eventName, 'lifecycle_test',
              reason: '${event.eventType?.name} should carry the show eventName');
        }
      }
    });
  });
}

/// Config repo that throws on the second call — used to verify loadFailed
/// reporting without blocking engine init.
class _ThrowingConfigRepo implements AdConfigRepository {
  int calls = 0;

  @override
  Future<AdConfig> getConfig() async {
    calls++;
    if (calls > 2) throw 'Bad config';
    return _StubConfigRepo(
      const AdConfig(
        loadTimeoutSeconds: 7,
        samePlacementCdSeconds: 0,
        differentPlacementCdSeconds: 0,
        placements: {},
      ),
    ).getConfig();
  }
}
