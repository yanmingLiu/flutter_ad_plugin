import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_ad_plugin/src/platform/ad_callback.dart';
import 'package:flutter_ad_plugin/src/platform/ad_adapter.dart';
import 'package:flutter_ad_plugin/src/platform/ad_registry.dart';
import 'package:flutter_ad_plugin/src/utils/cancellation_token.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {}
}

class _GatedSdkInitializer implements AdSourceSdkInitializer {
  _GatedSdkInitializer(this.gate);

  final Completer<void> gate;
  int initCount = 0;

  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {
    initCount++;
    await gate.future;
  }
}

class _FailOnceSdkInitializer implements AdSourceSdkInitializer {
  int initCount = 0;

  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {
    initCount++;
    if (initCount == 1) throw StateError('first init failed');
  }
}

class _TestConfigRepo extends Fake implements AdConfigRepository {
  final Map<String, dynamic> _json;

  _TestConfigRepo(this._json);

  @override
  Future<AdConfig> getConfig() async {
    return AdConfigParser().parse(_json);
  }
}

class _TestReporter implements AdEventReporter {
  final List<AdEvent> events = [];

  @override
  Future<void> report(AdEvent event) async {
    events.add(event);
  }
}

class _CountingAdapter implements AdTypeAdapter, NativeAdClickTracker {
  final AdSource _source;
  final AdType _type;
  final Object? loadError;
  final int? failAtLoadCount;
  final Map<int, Completer<void>> loadGates;
  final Completer<void>? showCloseGate;

  int loadCount = 0;
  int loadSuccessCount = 0;
  int showCount = 0;
  int disposeCount = 0;
  bool? lastRenderAsFullscreen;
  int? lastClosePassThroughPercent;
  bool clicked = false;
  final Set<VoidCallback> clickListeners = <VoidCallback>{};

  _CountingAdapter({
    required AdSource source,
    required AdType type,
    this.loadError,
    this.failAtLoadCount,
    this.loadGates = const {},
    this.showCloseGate,
  }) : _source = source,
       _type = type;

  @override
  AdSource get source => _source;

  @override
  AdType get type => _type;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    loadCount++;
    final loadGate = loadGates[loadCount];
    if (loadGate != null) await loadGate.future;
    lastRenderAsFullscreen = renderAsFullscreen;
    if (loadError != null || loadCount == failAtLoadCount) {
      return AdLoadResult.failure(
        type: _type,
        adUnitId: unit.id,
        error: loadError ?? 'load failed at $loadCount',
      );
    }
    final ad = Object();
    loadSuccessCount++;
    onCallback?.call(AdImpressionCallback(ad, null));
    return AdLoadResult.success(ad: ad, type: _type, adUnitId: unit.id);
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    required String eventName,
    required Object ad,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    void Function(AdRawCallback)? onCallback,
  }) async {
    showCount++;
    lastClosePassThroughPercent = closePassThroughPercent;
    onAdShowed?.call();
    if (showCloseGate != null) await showCloseGate!.future;
    onClosed?.call();
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {
    disposeCount++;
  }

  void notifyClicked() {
    clicked = true;
    for (final listener in List<VoidCallback>.of(clickListeners)) {
      listener();
    }
  }

  @override
  bool hasClicked(Object ad) => clicked;

  @override
  void addClickListener(Object ad, VoidCallback listener) {
    clickListeners.add(listener);
  }

  @override
  void removeClickListener(Object ad, VoidCallback listener) {
    clickListeners.remove(listener);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

void main() {
  group('AdPlugin', () {
    late _TestReporter reporter;
    late _TestConfigRepo configRepo;
    late AdPlugin plugin;
    late _CountingAdapter fullscreenAdapter;
    late _CountingAdapter nativeAdapter;

    setUp(() {
      reporter = _TestReporter();
      configRepo = _TestConfigRepo({
        'load_timeout': 7,
        'ad_cd': 30,
        'interstitial': [
          {
            'source': 'admob',
            'type': 'interstitial',
            'id': 'ca-app-pub-test/123',
            'weight': 1,
          },
        ],
        'home': [
          {
            'source': 'admob',
            'type': 'native',
            'id': 'ca-app-pub-test/456',
            'weight': 5,
          },
        ],
        'banner_bottom': [
          {
            'source': 'admob',
            'type': 'banner',
            'id': 'ca-app-pub-test/789',
            'weight': 1,
          },
        ],
        'fullscreen_native': [
          {
            'source': 'admob',
            'type': 'native',
            'id': 'ca-app-pub-test/fullscreen-native',
            'weight': 1,
          },
        ],
      });

      fullscreenAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.interstitial,
      );
      nativeAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.native,
      );

      plugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: configRepo,
          eventReporter: reporter,
          placementPolicies: {
            const PlacementType('fullscreen_native'): PlacementPolicy(
              isFullscreen: true,
              showNotReadyToast: false,
              allowedTypes: {AdType.native},
            ),
          },
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [
            fullscreenAdapter,
            nativeAdapter,
            _CountingAdapter(source: AdSource.admob, type: AdType.banner),
            _CountingAdapter(source: AdSource.admob, type: AdType.open),
            _CountingAdapter(source: AdSource.admob, type: AdType.rewarded),
          ],
        ),
      );
    });

    test('init completes without error', () async {
      await plugin.init();
      expect(plugin.isInitialized, isTrue);
    });

    test('init is idempotent', () async {
      await plugin.init();
      await plugin.init();
      expect(plugin.isInitialized, isTrue);
    });

    test('concurrent init shares one initialization', () async {
      final gate = Completer<void>();
      final initializer = _GatedSdkInitializer(gate);
      final concurrentPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: configRepo,
          eventReporter: reporter,
          sdkInitializers: [initializer],
          adapters: [fullscreenAdapter, nativeAdapter],
        ),
      );

      final first = concurrentPlugin.init();
      final second = concurrentPlugin.init();
      expect(initializer.initCount, 1);
      gate.complete();
      await Future.wait([first, second]);
      expect(concurrentPlugin.isInitialized, isTrue);
      await concurrentPlugin.dispose();
    });

    test('dispose before init is safe and prevents later init', () async {
      await plugin.dispose();
      await plugin.dispose();
      await expectLater(plugin.init(), throwsStateError);
    });

    test('init can retry after a failed attempt', () async {
      final initializer = _FailOnceSdkInitializer();
      final retryPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: configRepo,
          eventReporter: reporter,
          sdkInitializers: [initializer],
          adapters: [fullscreenAdapter],
        ),
      );

      await expectLater(retryPlugin.init(), throwsStateError);
      await retryPlugin.init();

      expect(initializer.initCount, 2);
      expect(retryPlugin.isInitialized, isTrue);
      await retryPlugin.dispose();
    });

    test('throws when used before init', () {
      expect(
        () => plugin.preload(PlacementType('home'), eventName: 'test'),
        throwsStateError,
      );
    });

    test('preload succeeds and reports events', () async {
      await plugin.init();
      final ok = await plugin.preload(
        const PlacementType('interstitial'),
        eventName: 'cold_start',
      );
      expect(ok, isTrue);
      final loadEvents = reporter.events.where(
        (e) =>
            e.eventType == AdEventType.loadSucceeded ||
            e.eventType == AdEventType.loadRequested,
      );
      expect(loadEvents.length, greaterThanOrEqualTo(2));
    });

    test('preload returns false when no units match', () async {
      await plugin.init();
      final ok = await plugin.preload(
        const PlacementType('unknown'),
        eventName: 'no_units',
      );
      expect(ok, isFalse);
    });

    test('missing adapter reports load failure without throwing', () async {
      final unsupportedPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: _TestConfigRepo({
            'unsupported': [
              {'source': 'max', 'type': 'interstitial', 'id': 'max-id'},
            ],
          }),
          eventReporter: reporter,
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [fullscreenAdapter],
        ),
      );
      await unsupportedPlugin.init();

      final loaded = await unsupportedPlugin.preload(
        const PlacementType('unsupported'),
        eventName: 'unsupported_load',
      );

      expect(loaded, isFalse);
      expect(
        reporter.events.any(
          (event) =>
              event.eventType == AdEventType.loadFailed &&
              event.errorReason!.contains('No adapter registered'),
        ),
        isTrue,
      );
      await unsupportedPlugin.dispose();
    });

    test('native refill preserves an existing cached ad', () async {
      final partialAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.native,
        failAtLoadCount: 2,
      );
      final refillPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: _TestConfigRepo({
            'home': [
              {
                'source': 'admob',
                'type': 'native',
                'ad_id': 'native-1',
                'ad_id2': 'native-2',
              },
            ],
          }),
          eventReporter: reporter,
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [partialAdapter],
        ),
      );
      await refillPlugin.init();
      await refillPlugin.loadNative(
        const PlacementType('home'),
        eventName: 'first_load',
      );
      await refillPlugin.loadNative(
        const PlacementType('home'),
        eventName: 'refill',
      );

      expect(
        refillPlugin.getNativeAds(
          const PlacementType('home'),
          eventName: 'home_show',
        ),
        hasLength(2),
      );
      await refillPlugin.dispose();
      expect(partialAdapter.disposeCount, 2);
    });

    test('dispose during load disposes the late result', () async {
      final gate = Completer<void>();
      final delayedAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.interstitial,
        loadGates: {1: gate},
      );
      final delayedPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: configRepo,
          eventReporter: reporter,
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [delayedAdapter],
        ),
      );
      await delayedPlugin.init();
      final load = delayedPlugin.preload(
        const PlacementType('interstitial'),
        eventName: 'delayed_load',
      );
      await _waitUntil(() => delayedAdapter.loadCount == 1);
      await delayedPlugin.dispose();
      gate.complete();

      expect(await load, isFalse);
      expect(delayedAdapter.disposeCount, 1);
    });

    test('preloadPlacements waits for all loads', () async {
      final gate = Completer<void>();
      final delayedAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.interstitial,
        loadGates: {1: gate},
      );
      final delayedPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: configRepo,
          eventReporter: reporter,
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [delayedAdapter],
        ),
      );
      await delayedPlugin.init();
      var completed = false;
      final preload = delayedPlugin.preloadPlacements([
        const PlacementType('interstitial'),
      ], eventName: 'batch_load')..then((_) => completed = true);
      await _waitUntil(() => delayedAdapter.loadCount == 1);
      expect(completed, isFalse);

      gate.complete();
      await preload;
      expect(completed, isTrue);
      await delayedPlugin.dispose();
    });

    test('fullscreen show prefers level_h and applies ad_cd', () async {
      final poolAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.interstitial,
      );
      final openNativeAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.native,
      );
      final poolPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: _TestConfigRepo({
            'ad_cd': 30,
            'common_placements': ['behavior'],
            'high_value_placement': 'level_h',
            'open': [
              {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'open-id'},
              {
                'source': 'admob',
                'weight': 2,
                'type': 'native',
                'id': 'open-native-id',
              },
            ],
            'behavior': [
              {
                'ad_source': 'admob',
                'ad_weight': 1,
                'ad_type': 'interstitial',
                'ad_id': 'common-id',
              },
            ],
            'level_h': [
              {
                'ad_source': 'admob',
                'ad_weight': 1,
                'ad_type': 'interstitial',
                'ad_id': 'high-id',
              },
            ],
          }),
          eventReporter: reporter,
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [
            poolAdapter,
            openNativeAdapter,
            _CountingAdapter(source: AdSource.admob, type: AdType.open),
          ],
        ),
      );
      await poolPlugin.init();
      await poolPlugin.preload(
        const PlacementType('open'),
        eventName: 'open_preload',
      );
      expect(openNativeAdapter.loadCount, 1);

      final result = await poolPlugin.show(
        const PlacementType('open'),
        eventName: 'open_show',
      );
      expect(result.shown, isTrue);
      expect(result.requestedPlacement, const PlacementType('open'));
      expect(result.shownPlacement, const PlacementType('level_h'));
      expect(result.source, AdSource.admob);
      expect(result.type, AdType.interstitial);
      expect(result.adUnitId, 'high-id');
      expect(
        reporter.events
            .where((event) => event.eventType == AdEventType.show)
            .last
            .adUnitId,
        'high-id',
      );
      final showEvent = reporter.events
          .where((event) => event.eventType == AdEventType.show)
          .last;
      expect(showEvent.placement, const PlacementType('level_h'));
      expect(showEvent.requestedPlacement, const PlacementType('open'));

      final blocked = await poolPlugin.show(
        const PlacementType('open'),
        eventName: 'open_show_in_cd',
      );
      expect(blocked.shown, isFalse);
      expect(blocked.requestedPlacement, const PlacementType('open'));
      expect(blocked.shownPlacement, isNull);
      expect(blocked.errorReason, 'in_cd');
      expect(
        reporter.events
            .where((event) => event.eventType == AdEventType.showFail)
            .last
            .errorReason,
        'in_cd',
      );
      await poolPlugin.dispose();
    });

    test('non-open fullscreen placement uses behavior inventory', () async {
      final behaviorAdapter = _CountingAdapter(
        source: AdSource.max,
        type: AdType.interstitial,
      );
      final messageAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.interstitial,
      );
      final inventoryPlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: _TestConfigRepo({
            'common_placements': ['behavior', 'behavior2'],
            'behavior': [
              {
                'ad_source': 'max',
                'ad_weight': 1,
                'ad_type': 'interstitial',
                'ad_id': 'behavior-id',
              },
            ],
            'message': [
              {
                'ad_source': 'admob',
                'ad_weight': 1,
                'ad_type': 'interstitial',
                'ad_id': 'message-id',
              },
            ],
          }),
          eventReporter: reporter,
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [behaviorAdapter, messageAdapter],
        ),
      );
      await inventoryPlugin.init();

      expect(
        await inventoryPlugin.preload(
          const PlacementType('message'),
          eventName: 'message_preload',
        ),
        isTrue,
      );
      expect(behaviorAdapter.loadCount, 1);
      expect(messageAdapter.loadCount, 0);

      final result = await inventoryPlugin.show(
        const PlacementType('message'),
        eventName: 'message_show',
      );
      expect(result.shown, isTrue);
      expect(result.requestedPlacement, const PlacementType('message'));
      expect(result.shownPlacement, const PlacementType('behavior'));
      await inventoryPlugin.dispose();
    });

    test(
      'showSequence shows behavior2 only when it loads before behavior closes',
      () async {
        final behaviorClose = Completer<void>();
        final behavior2Load = Completer<void>();
        final behaviorAdapter = _CountingAdapter(
          source: AdSource.max,
          type: AdType.interstitial,
          showCloseGate: behaviorClose,
        );
        final behavior2Adapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.rewarded,
          loadGates: {1: behavior2Load},
        );
        final sequencePlugin = AdPlugin(
          config: AdPluginConfig(
            configRepository: _TestConfigRepo({
              'ad_cd': 30,
              'common_placements': ['behavior', 'behavior2'],
              'behavior': [
                {
                  'ad_source': 'max',
                  'ad_weight': 1,
                  'ad_type': 'interstitial',
                  'ad_id': 'behavior-id',
                },
              ],
              'behavior2': [
                {
                  'ad_source': 'admob',
                  'ad_weight': 1,
                  'ad_type': 'rewarded',
                  'ad_id': 'behavior2-id',
                },
              ],
            }),
            eventReporter: reporter,
            sdkInitializers: [_MockSdkInitializer()],
            adapters: [behaviorAdapter, behavior2Adapter],
          ),
        );
        await sequencePlugin.init();
        await sequencePlugin.preload(
          const PlacementType('behavior'),
          eventName: 'behavior_preload',
        );

        final showFuture = sequencePlugin.showSequence(
          const PlacementType('play_middle'),
          eventName: 'behavior_sequence',
        );
        await _waitUntil(
          () =>
              behaviorAdapter.showCount == 1 && behavior2Adapter.loadCount == 1,
        );
        behavior2Load.complete();
        await _waitUntil(() => behavior2Adapter.loadSuccessCount == 1);
        behaviorClose.complete();
        final result = await showFuture;

        expect(result.shown, isTrue);
        expect(result.shownCount, 2);
        expect(behaviorAdapter.showCount, 1);
        expect(behavior2Adapter.showCount, 1);
        expect(behavior2Adapter.loadCount, greaterThanOrEqualTo(1));
        await sequencePlugin.dispose();
      },
    );

    test(
      'showSequence shows only high value when both common pools start empty',
      () async {
        final highClose = Completer<void>();
        final highRefill = Completer<void>();
        final highAdapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.rewardedInterstitial,
          loadGates: {2: highRefill},
          showCloseGate: highClose,
        );
        final behaviorAdapter = _CountingAdapter(
          source: AdSource.max,
          type: AdType.interstitial,
          failAtLoadCount: 1,
        );
        final behavior2Adapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.rewarded,
          loadError: 'behavior2 unavailable',
        );
        final sequencePlugin = AdPlugin(
          config: AdPluginConfig(
            configRepository: _TestConfigRepo({
              'common_placements': ['behavior', 'behavior2'],
              'high_value_placement': 'level_h',
              'level_h': [
                {
                  'ad_source': 'admob',
                  'ad_weight': 1,
                  'ad_type': 'rewarded_interstitial',
                  'ad_id': 'high-id',
                },
              ],
              'behavior': [
                {
                  'ad_source': 'max',
                  'ad_weight': 1,
                  'ad_type': 'interstitial',
                  'ad_id': 'behavior-id',
                },
              ],
              'behavior2': [
                {
                  'ad_source': 'admob',
                  'ad_weight': 1,
                  'ad_type': 'rewarded',
                  'ad_id': 'behavior2-id',
                },
              ],
            }),
            eventReporter: reporter,
            sdkInitializers: [_MockSdkInitializer()],
            adapters: [highAdapter, behaviorAdapter, behavior2Adapter],
          ),
        );
        await sequencePlugin.init();
        await sequencePlugin.preload(
          const PlacementType('behavior'),
          eventName: 'cold_start',
        );
        await sequencePlugin.preload(
          const PlacementType('behavior2'),
          eventName: 'cold_start',
        );

        final showFuture = sequencePlugin.showSequence(
          const PlacementType('behavior'),
          eventName: 'behavior_sequence_show',
        );
        await _waitUntil(
          () =>
              highAdapter.showCount == 1 &&
              behaviorAdapter.loadSuccessCount == 1,
        );
        highClose.complete();
        final result = await showFuture;

        expect(result.shown, isTrue);
        expect(result.shownCount, 1);
        expect(highAdapter.showCount, 1);
        expect(behaviorAdapter.showCount, 0);
        expect(behavior2Adapter.showCount, 0);
        expect(behaviorAdapter.loadCount, greaterThanOrEqualTo(2));
        expect(behavior2Adapter.loadCount, greaterThanOrEqualTo(2));
        highRefill.complete();
        await sequencePlugin.dispose();
      },
    );

    test(
      'showSequence does not reuse high value in the second round',
      () async {
        final firstHighClose = Completer<void>();
        final highRefill = Completer<void>();
        final highAdapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.rewardedInterstitial,
          loadGates: {2: highRefill},
          showCloseGate: firstHighClose,
        );
        final behaviorAdapter = _CountingAdapter(
          source: AdSource.max,
          type: AdType.interstitial,
        );
        final behavior2Adapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.rewarded,
        );
        final sequencePlugin = AdPlugin(
          config: AdPluginConfig(
            configRepository: _TestConfigRepo({
              'common_placements': ['behavior', 'behavior2'],
              'high_value_placement': 'level_h',
              'level_h': [
                {
                  'ad_source': 'admob',
                  'ad_weight': 1,
                  'ad_type': 'rewarded_interstitial',
                  'ad_id': 'high-id',
                },
              ],
              'behavior': [
                {
                  'ad_source': 'max',
                  'ad_weight': 1,
                  'ad_type': 'interstitial',
                  'ad_id': 'behavior-id',
                },
              ],
              'behavior2': [
                {
                  'ad_source': 'admob',
                  'ad_weight': 1,
                  'ad_type': 'rewarded',
                  'ad_id': 'behavior2-id',
                },
              ],
            }),
            eventReporter: reporter,
            sdkInitializers: [_MockSdkInitializer()],
            adapters: [highAdapter, behaviorAdapter, behavior2Adapter],
          ),
        );
        await sequencePlugin.init();
        await sequencePlugin.preload(
          const PlacementType('behavior'),
          eventName: 'cold_start',
        );
        await sequencePlugin.preload(
          const PlacementType('behavior2'),
          eventName: 'cold_start',
        );

        final showFuture = sequencePlugin.showSequence(
          const PlacementType('behavior'),
          eventName: 'behavior_sequence_show',
        );
        await _waitUntil(() => highAdapter.showCount == 1);
        firstHighClose.complete();

        expect((await showFuture).shown, isTrue);
        expect(highAdapter.showCount, 1);
        expect(behaviorAdapter.showCount, 0);
        expect(behavior2Adapter.showCount, 1);
        await _waitUntil(() => highAdapter.loadCount == 2);
        highRefill.complete();
        await sequencePlugin.dispose();
      },
    );

    test(
      'showSequence can use high value loaded during the first round',
      () async {
        final behaviorClose = Completer<void>();
        final highSecondLoad = Completer<void>();
        final highAdapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.rewardedInterstitial,
          failAtLoadCount: 1,
          loadGates: {2: highSecondLoad},
        );
        final behaviorAdapter = _CountingAdapter(
          source: AdSource.max,
          type: AdType.interstitial,
          showCloseGate: behaviorClose,
        );
        final behavior2Adapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.rewarded,
        );
        final sequencePlugin = AdPlugin(
          config: AdPluginConfig(
            configRepository: _TestConfigRepo({
              'common_placements': ['behavior', 'behavior2'],
              'high_value_placement': 'level_h',
              'level_h': [
                {
                  'ad_source': 'admob',
                  'ad_weight': 1,
                  'ad_type': 'rewarded_interstitial',
                  'ad_id': 'high-id',
                },
              ],
              'behavior': [
                {
                  'ad_source': 'max',
                  'ad_weight': 1,
                  'ad_type': 'interstitial',
                  'ad_id': 'behavior-id',
                },
              ],
              'behavior2': [
                {
                  'ad_source': 'admob',
                  'ad_weight': 1,
                  'ad_type': 'rewarded',
                  'ad_id': 'behavior2-id',
                },
              ],
            }),
            eventReporter: reporter,
            sdkInitializers: [_MockSdkInitializer()],
            adapters: [highAdapter, behaviorAdapter, behavior2Adapter],
          ),
        );
        await sequencePlugin.init();
        await sequencePlugin.preload(
          const PlacementType('behavior'),
          eventName: 'cold_start',
        );
        final behavior2Preload = sequencePlugin.preload(
          const PlacementType('behavior2'),
          eventName: 'cold_start',
        );
        await _waitUntil(
          () =>
              behavior2Adapter.loadSuccessCount == 1 &&
              highAdapter.loadCount == 2,
        );

        final showFuture = sequencePlugin.showSequence(
          const PlacementType('behavior'),
          eventName: 'behavior_sequence_show',
        );
        await _waitUntil(() => behaviorAdapter.showCount == 1);
        highSecondLoad.complete();
        await _waitUntil(() => highAdapter.loadSuccessCount == 1);
        behaviorClose.complete();

        expect(await behavior2Preload, isTrue);
        expect((await showFuture).shown, isTrue);
        expect(behaviorAdapter.showCount, 1);
        expect(highAdapter.showCount, 1);
        expect(behavior2Adapter.showCount, 0);
        await sequencePlugin.dispose();
      },
    );

    test('loadNative succeeds', () async {
      await plugin.init();
      final ok = await plugin.loadNative(
        const PlacementType('home'),
        eventName: 'home_show',
      );
      expect(ok, isTrue);
    });

    test('getNativeAd returns cached ad', () async {
      await plugin.init();
      await plugin.loadNative(PlacementType('home'), eventName: 'home_show');
      final ad = plugin.getNativeAd(
        const PlacementType('home'),
        eventName: 'home_show',
      );
      expect(ad, isNotNull);
    });

    test('getNativeAds returns multiple ads', () async {
      await plugin.init();
      await plugin.loadNative(PlacementType('home'), eventName: 'home_show');
      final ads = plugin.getNativeAds(
        const PlacementType('home'),
        count: 1,
        eventName: 'home_show',
      );
      expect(ads, isNotEmpty);
    });

    test('native cacheId keeps home tab caches independent', () async {
      await plugin.init();
      const placement = PlacementType('home');
      await plugin.loadNative(
        placement,
        eventName: 'home_tab_1_load',
        cacheId: 'tab-1',
      );
      await plugin.loadNative(
        placement,
        eventName: 'home_tab_2_load',
        cacheId: 'tab-2',
      );

      final tab2Ad = plugin.getNativeAd(
        placement,
        eventName: 'home_tab_2_show',
        cacheId: 'tab-2',
      );
      plugin.disposeNativeAd(placement, cacheId: 'tab-1');

      expect(
        plugin.getNativeAd(
          placement,
          eventName: 'home_tab_1_show',
          cacheId: 'tab-1',
        ),
        isNull,
      );
      expect(
        plugin.getNativeAd(
          placement,
          eventName: 'home_tab_2_show_again',
          cacheId: 'tab-2',
        ),
        same(tab2Ad),
      );
    });

    test('double_native discards partial cache when one id fails', () async {
      final partialAdapter = _CountingAdapter(
        source: AdSource.admob,
        type: AdType.native,
        failAtLoadCount: 2,
      );
      final doubleNativePlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: _TestConfigRepo({
            'play_middle': [
              {
                'ad_source': 'admob',
                'ad_weight': 1,
                'ad_type': 'double_native',
                'ad_id': 'native-1',
                'ad_id2': 'native-2',
              },
            ],
          }),
          eventReporter: reporter,
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [partialAdapter],
        ),
      );
      await doubleNativePlugin.init();

      final loaded = await doubleNativePlugin.loadNative(
        const PlacementType('play_middle'),
        eventName: 'play_middle_load',
      );

      expect(loaded, isFalse);
      expect(
        doubleNativePlugin.getNativeAds(
          const PlacementType('play_middle'),
          eventName: 'play_middle_show',
        ),
        isEmpty,
      );
      expect(partialAdapter.disposeCount, 1);
      await doubleNativePlugin.dispose();
    });

    test('loadBanner succeeds', () async {
      await plugin.init();
      final ok = await plugin.loadBanner(
        const PlacementType('banner_bottom'),
        eventName: 'article',
      );
      expect(ok, isTrue);
    });

    test('getBannerAd returns cached banner', () async {
      await plugin.init();
      await plugin.loadBanner(
        PlacementType('banner_bottom'),
        eventName: 'article',
      );
      final ad = plugin.getBannerAd(
        PlacementType('banner_bottom'),
        eventName: 'banner_show',
      );
      expect(ad, isNotNull);
      expect(reporter.events.last.eventName, 'banner_show');
    });

    test('disposeBannerAd clears cache', () async {
      await plugin.init();
      await plugin.loadBanner(
        PlacementType('banner_bottom'),
        eventName: 'article',
      );
      plugin.disposeBannerAd(PlacementType('banner_bottom'));
      expect(
        plugin.getBannerAd(
          PlacementType('banner_bottom'),
          eventName: 'banner_show',
        ),
        isNull,
      );
    });

    test('widgetFactory returns valid factory', () async {
      await plugin.init();
      expect(plugin.widgetFactory, isNotNull);
    });

    test('preload passes fullscreen native render flag', () async {
      await plugin.init();
      final ok = await plugin.preload(
        const PlacementType('fullscreen_native'),
        eventName: 'fullscreen_native_preload',
      );

      expect(ok, isTrue);
      expect(nativeAdapter.lastRenderAsFullscreen, isTrue);
    });

    testWidgets('fullscreen native requires a host presenter', (tester) async {
      await plugin.init();
      await plugin.preload(
        const PlacementType('fullscreen_native'),
        eventName: 'fullscreen_native_preload',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      final result = await plugin.show(
        const PlacementType('fullscreen_native'),
        context: tester.element(find.byType(SizedBox)),
        eventName: 'fullscreen_native_show',
      );

      expect(result.shown, isFalse);
      expect(result.errorReason, 'missing_fullscreen_native_presenter');
      expect(nativeAdapter.disposeCount, 1);
    });

    test(
      'fullscreen native cache miss returns immediately and starts load',
      () async {
        final notReadyEvents = <AdNotReadyEvent>[];
        final failingNativeAdapter = _CountingAdapter(
          source: AdSource.admob,
          type: AdType.native,
          loadError: 'NativeAdError: missing fullScreenNative factory',
        );
        final failingPlugin = AdPlugin(
          config: AdPluginConfig(
            configRepository: configRepo,
            eventReporter: reporter,
            onAdNotReady: notReadyEvents.add,
            placementPolicies: {
              const PlacementType('fullscreen_native'): PlacementPolicy(
                isFullscreen: true,
                showNotReadyToast: true,
                allowedTypes: {AdType.native},
                notReadyMsg: 'Fullscreen native ad is still loading.',
              ),
            },
            sdkInitializers: [_MockSdkInitializer()],
            adapters: [
              _CountingAdapter(
                source: AdSource.admob,
                type: AdType.interstitial,
              ),
              failingNativeAdapter,
              _CountingAdapter(source: AdSource.admob, type: AdType.banner),
              _CountingAdapter(source: AdSource.admob, type: AdType.open),
              _CountingAdapter(source: AdSource.admob, type: AdType.rewarded),
            ],
          ),
        );

        await failingPlugin.init();
        final shown = await failingPlugin.show(
          const PlacementType('fullscreen_native'),
          eventName: 'fullscreen_native_show',
        );

        expect(shown.shown, isFalse);
        expect(shown.errorReason, 'no_cache');
        expect(notReadyEvents, hasLength(1));
        expect(
          notReadyEvents.single.message,
          'Fullscreen native ad is still loading.',
        );
        await Future<void>.delayed(Duration.zero);
        expect(failingNativeAdapter.loadCount, 1);
        expect(failingNativeAdapter.lastRenderAsFullscreen, isTrue);
        await failingPlugin.dispose();
      },
    );

    testWidgets('fullscreen native show waits for dialog close', (
      tester,
    ) async {
      final closeGate = Completer<void>();
      final presenterEntered = Completer<void>();
      int? receivedClosePercent;
      final nativePlugin = AdPlugin(
        config: AdPluginConfig(
          configRepository: configRepo,
          eventReporter: reporter,
          placementPolicies: {
            const PlacementType('fullscreen_native'): PlacementPolicy(
              isFullscreen: true,
              allowedTypes: {AdType.native},
            ),
          },
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [nativeAdapter],
          fullscreenNativePresenter:
              ({
                required context,
                required placement,
                required eventName,
                required ad,
                required clickTracker,
                required closePassThroughPercent,
                required onClosed,
              }) async {
                receivedClosePercent = closePassThroughPercent;
                presenterEntered.complete();
                await closeGate.future;
                onClosed();
                return true;
              },
        ),
      );
      await nativePlugin.init();
      await nativePlugin.preload(
        const PlacementType('fullscreen_native'),
        eventName: 'fullscreen_native_preload',
      );

      Future<AdShowResult>? showFuture;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showFuture = nativePlugin.show(
                    const PlacementType('fullscreen_native'),
                    context: context,
                    eventName: 'fullscreen_native_show',
                    closePassThroughPercent: 100,
                  );
                },
                child: const Text('show fullscreen native'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('show fullscreen native'));
      await tester.pump();
      await presenterEntered.future;
      expect(nativeAdapter.showCount, 1);
      expect(nativeAdapter.lastClosePassThroughPercent, 100);
      expect(receivedClosePercent, 100);
      expect(showFuture, isNotNull);

      closeGate.complete();
      await tester.pump();

      expect((await showFuture)?.shown, isTrue);
      expect(nativeAdapter.disposeCount, 1);
      await _waitUntil(() => nativeAdapter.loadCount >= 2);
      expect(nativeAdapter.loadCount, greaterThanOrEqualTo(2));
      expect(
        reporter.events.map((event) => event.eventType),
        contains(AdEventType.close),
      );
      await nativePlugin.dispose();
    });

    test('dispose clears state', () async {
      await plugin.init();
      await plugin.loadNative(PlacementType('home'), eventName: 'home_show');
      await plugin.dispose();
      expect(
        () => plugin.loadNative(PlacementType('home'), eventName: 'x'),
        throwsStateError,
      );
    });

    test('multiple init calls are safe', () async {
      await plugin.init();
      await plugin.init();
      expect(plugin.isInitialized, isTrue);
    });
  });

  group('AdPluginConfig', () {
    test('stores all fields correctly', () {
      final config = AdPluginConfig(
        configRepository: _TestConfigRepo({}),
        eventReporter: _TestReporter(),
        nativeAdCloseClickPercent: 15,
        verboseLogging: true,
        enableHealthMetrics: true,
      );
      expect(config.nativeAdCloseClickPercent, 15);
      expect(config.verboseLogging, isTrue);
      expect(config.enableHealthMetrics, isTrue);
    });
  });
}
