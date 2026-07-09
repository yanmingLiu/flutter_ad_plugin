import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:flutter_ad_plugin/src/core/ad_models.dart';
import 'package:flutter_ad_plugin/src/platform/ad_callback.dart';
import 'package:flutter_ad_plugin/src/platform/ad_adapter.dart';
import 'package:flutter_ad_plugin/src/platform/ad_registry.dart';
import 'package:flutter_ad_plugin/src/ui/fullscreen_native_ad_dialog.dart';
import 'package:flutter_ad_plugin/src/utils/cancellation_token.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {}
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

  int loadCount = 0;
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
    lastRenderAsFullscreen = renderAsFullscreen;
    if (loadError != null) {
      return AdLoadResult.failure(
        type: _type,
        adUnitId: unit.id,
        error: loadError,
      );
    }
    final ad = Object();
    onCallback?.call(AdImpressionCallback(ad, null));
    return AdLoadResult.success(ad: ad, type: _type, adUnitId: unit.id);
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    String? placementLabel,
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
        'same_placement_cd': 30,
        'different_placement_cd': 30,
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
              applySamePlacementCd: false,
              applyDifferentPlacementCd: false,
              contributesToGlobalCooldown: false,
              showNotReadyToast: false,
              waitForLoadOnShow: true,
              preferHighValueOnShow: false,
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
      final ad = plugin.getBannerAd(PlacementType('banner_bottom'));
      expect(ad, isNotNull);
    });

    test('disposeBannerAd clears cache', () async {
      await plugin.init();
      await plugin.loadBanner(
        PlacementType('banner_bottom'),
        eventName: 'article',
      );
      plugin.disposeBannerAd(PlacementType('banner_bottom'));
      expect(plugin.getBannerAd(PlacementType('banner_bottom')), isNull);
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

    test('fullscreen native not-ready includes last load error', () async {
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
              applySamePlacementCd: false,
              applyDifferentPlacementCd: false,
              contributesToGlobalCooldown: false,
              showNotReadyToast: true,
              waitForLoadOnShow: true,
              preferHighValueOnShow: false,
              allowedTypes: {AdType.native},
              notReadyMsg: 'Fullscreen native ad is still loading.',
            ),
          },
          sdkInitializers: [_MockSdkInitializer()],
          adapters: [
            _CountingAdapter(source: AdSource.admob, type: AdType.interstitial),
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

      expect(shown, isFalse);
      expect(notReadyEvents, hasLength(1));
      expect(
        notReadyEvents.single.message,
        contains('NativeAdError: missing fullScreenNative factory'),
      );
      expect(failingNativeAdapter.lastRenderAsFullscreen, isTrue);
      await failingPlugin.dispose();
    });

    testWidgets('fullscreen native show waits for dialog close', (
      tester,
    ) async {
      await plugin.init();
      await plugin.preload(
        const PlacementType('fullscreen_native'),
        eventName: 'fullscreen_native_preload',
      );

      Future<bool>? showFuture;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showFuture = plugin.show(
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
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(FullscreenNativeAdDialog.advertisementLabelKey),
        findsOneWidget,
      );
      expect(
        find.byKey(FullscreenNativeAdDialog.closeButtonKey),
        findsOneWidget,
      );
      expect(nativeAdapter.showCount, 1);
      expect(nativeAdapter.lastClosePassThroughPercent, 100);

      nativeAdapter.notifyClicked();
      await tester.pump();

      await tester.tap(find.byKey(FullscreenNativeAdDialog.closeButtonKey));
      await tester.pumpAndSettle();

      expect(await showFuture, isTrue);
      expect(nativeAdapter.disposeCount, 1);
      expect(nativeAdapter.loadCount, greaterThanOrEqualTo(2));
      expect(
        reporter.events.map((event) => event.eventType),
        contains(AdEventType.close),
      );
      await plugin.dispose();
    });

    test('dispose cancels timers and clears state', () async {
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
