/// Recommended entry point for host applications.
///
/// The public path is intentionally short:
/// `AdPlugin -> AdPlatform -> AdEvent / AdShowResult`.
///
/// ```dart
/// final ads = AdPlugin(
///   config: adConfigJson,
///   platforms: [AdmobPlatform()],
///   onEvent: (event) => analytics.report(event),
/// );
///
/// await ads.init();
/// await ads.preload('home', eventName: 'home_enter');
/// ```
library;

import 'package:flutter/widgets.dart';

import 'engine.dart';
import 'models.dart';
import 'platform.dart';

export 'models.dart'
    show
        AdEvent,
        AdEventType,
        AdNotReadyEvent,
        AdShowResult,
        AdSequenceShowResult;
export 'flutter_ad_admob.dart' show AdmobPlatform;
export 'flutter_ad_max.dart' show MaxPlatform;
export 'flutter_ad_topon.dart' show TopOnPlatform;

/// Main entry point for the ad plugin.
///
/// The host only supplies JSON-style ad config, platform instances and an
/// optional event callback. All registry, adapter and engine details stay
/// behind this class.
class AdPlugin {
  AdPlugin({
    required Map<String, dynamic> config,
    required List<AdPlatform> platforms,
    Future<Map<String, dynamic>> Function()? configLoader,
    void Function(AdEvent event)? onEvent,
    void Function(AdNotReadyEvent event)? onAdNotReady,
    bool verboseLogging = false,
  }) : _options = _AdPluginOptions(
         config: Map<String, dynamic>.unmodifiable(config),
         configLoader: configLoader,
         platforms: List<AdPlatform>.unmodifiable(platforms),
         onEvent: onEvent,
         onAdNotReady: onAdNotReady,
         verboseLogging: verboseLogging,
       ) {
    if (platforms.isEmpty) {
      throw ArgumentError.value(
        platforms,
        'platforms',
        'At least one platform is required',
      );
    }
  }

  final _AdPluginOptions _options;

  late final AdAdapterRegistry _adapterRegistry;
  late final AdCacheService _cache;
  late final AdDisplayGuard _guard;
  late final AdLoaderService _loader;
  late final AdPresenter _presenter;

  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initializing;

  bool get isInitialized => _initialized;

  /// Initializes SDKs, loads config and prepares the ad engine.
  Future<void> init() async {
    if (_initialized) return;
    if (_disposed) {
      throw StateError('AdPlugin has been disposed and cannot be reused.');
    }
    final pending = _initializing;
    if (pending != null) return pending;
    final future = _initialize();
    _initializing = future;
    try {
      await future;
    } finally {
      if (identical(_initializing, future)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    final logger = AppLogger(verboseEnabled: _options.verboseLogging);
    final adapters = AdAdapterRegistry(
      fullscreenAdapters: [
        for (final platform in _options.platforms)
          ...platform.fullscreenAdapters,
      ],
      inlineAdapters: [
        for (final platform in _options.platforms) ...platform.inlineAdapters,
      ],
    );
    final cache = AdCacheService();
    final guard = AdDisplayGuard();
    final eventMapper = AdEventMapper();
    final reporter = _CallbackEventReporter(_options.onEvent);
    final configRepository = _MapConfigRepository(
      _options.config,
      _options.configLoader,
    );
    final loader = AdLoaderService(
      configRepository: configRepository,
      adapterRegistry: adapters,
      cache: cache,
      eventMapper: eventMapper,
      reporter: reporter,
      logger: logger,
    );
    final presenter = AdPresenter(
      configRepository: configRepository,
      adapterRegistry: adapters,
      cache: cache,
      guard: guard,
      eventMapper: eventMapper,
      reporter: reporter,
      loader: loader,
      logger: logger,
    );

    try {
      for (final platform in _options.platforms) {
        await platform.init();
      }
      await configRepository.getConfig();
      if (_disposed) return;

      _adapterRegistry = adapters;
      _cache = cache;
      _guard = guard;
      _loader = loader;
      _presenter = presenter;
      _initialized = true;
    } finally {
      if (!_initialized) {
        loader.dispose();
        _disposePlatforms();
      }
    }
  }

  /// Releases SDK listeners, timers and cached ads.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pending = _initializing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Initialization owns no published resources until it succeeds.
      }
    }
    if (!_initialized) return;
    _loader.dispose();
    for (final slot in _cache.drainAll()) {
      _adapterRegistry.dispose(slot.source, slot.type, slot.ad);
    }
    _guard.resetForTesting();
    _disposePlatforms();
    _initialized = false;
  }

  Future<bool> preload(Object placement, {required String eventName}) {
    _assertInitialized();
    return _loader.preload(_placement(placement), eventName: eventName);
  }

  Future<void> preloadPlacements(
    Iterable<Object> placements, {
    required String eventName,
  }) {
    _assertInitialized();
    return _loader.preloadPlacements(
      placements.map(_placement),
      eventName: eventName,
    );
  }

  Future<AdShowResult> show(
    Object placement, {
    BuildContext? context,
    required String eventName,
    Map<String, dynamic>? extras,
    int closePassThroughPercent = 0,
  }) {
    _assertInitialized();
    return _presenter.show(
      _placement(placement),
      context: context,
      eventName: eventName,
      extras: extras,
      closePassThroughPercent: closePassThroughPercent,
      onAdNotReady: _options.onAdNotReady,
    );
  }

  Future<AdSequenceShowResult> showSequence(
    Object placement, {
    BuildContext? context,
    required String eventName,
    Map<String, dynamic>? extras,
    int closePassThroughPercent = 0,
  }) {
    _assertInitialized();
    return _presenter.showSequence(
      _placement(placement),
      context: context,
      eventName: eventName,
      extras: extras,
      closePassThroughPercent: closePassThroughPercent,
      onAdNotReady: _options.onAdNotReady,
    );
  }

  Future<bool> loadNative(
    Object placement, {
    required String eventName,
    String? cacheId,
  }) {
    _assertInitialized();
    return _loader.preloadNative(
      _placement(placement),
      eventName: eventName,
      cacheId: cacheId,
    );
  }

  Object? getNativeAd(
    Object placement, {
    String? cacheId,
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    _assertInitialized();
    return _presenter.getNativeAd(
      _placement(placement),
      cacheId: cacheId,
      eventName: eventName,
      extras: extras,
    );
  }

  List<Object> getNativeAds(
    Object placement, {
    int count = 2,
    String? cacheId,
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    _assertInitialized();
    return _presenter.getNativeAds(
      _placement(placement),
      count: count,
      cacheId: cacheId,
      eventName: eventName,
      extras: extras,
    );
  }

  Future<bool> loadBanner(Object placement, {required String eventName}) {
    _assertInitialized();
    return _loader.preloadBanner(_placement(placement), eventName: eventName);
  }

  Object? getBannerAd(
    Object placement, {
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    _assertInitialized();
    return _presenter.getBannerAd(
      _placement(placement),
      eventName: eventName,
      extras: extras,
    );
  }

  List<Object> getBannerAds(
    Object placement, {
    int count = 2,
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    _assertInitialized();
    return _presenter.getBannerAds(
      _placement(placement),
      count: count,
      eventName: eventName,
      extras: extras,
    );
  }

  Widget bannerWidget(Object ad) {
    _assertInitialized();
    for (final platform in _options.platforms) {
      final widget = platform.bannerWidget(ad);
      if (widget != null) return widget;
    }
    return const SizedBox.shrink();
  }

  Widget nativeWidget(Object ad, {double height = 280, bool expand = false}) {
    _assertInitialized();
    for (final platform in _options.platforms) {
      final widget = platform.nativeWidget(ad, height: height, expand: expand);
      if (widget != null) return widget;
    }
    return const SizedBox.shrink();
  }

  void disposeBannerAd(Object placement) {
    _assertInitialized();
    _presenter.disposeBannerAd(_placement(placement));
  }

  void disposeNativeAd(Object placement, {String? cacheId}) {
    _assertInitialized();
    _presenter.disposeNativeAd(_placement(placement), cacheId: cacheId);
  }

  void _disposePlatforms() {
    for (final platform in _options.platforms) {
      platform.dispose();
    }
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError('AdPlugin not initialized. Call init() first.');
    }
  }
}

PlacementType _placement(Object value) {
  return value is PlacementType ? value : PlacementType(value.toString());
}

class _AdPluginOptions {
  const _AdPluginOptions({
    required this.config,
    required this.platforms,
    required this.configLoader,
    required this.onEvent,
    required this.onAdNotReady,
    required this.verboseLogging,
  });

  final Map<String, dynamic> config;
  final Future<Map<String, dynamic>> Function()? configLoader;
  final List<AdPlatform> platforms;
  final void Function(AdEvent event)? onEvent;
  final void Function(AdNotReadyEvent event)? onAdNotReady;
  final bool verboseLogging;
}

class _CallbackEventReporter implements AdEventReporter {
  const _CallbackEventReporter(this._onEvent);

  final void Function(AdEvent event)? _onEvent;

  @override
  Future<void> report(AdEvent event) async {
    _onEvent?.call(event);
  }
}

class _MapConfigRepository implements AdConfigRepository {
  _MapConfigRepository(this._fallback, this._loader);

  final Map<String, dynamic> _fallback;
  final Future<Map<String, dynamic>> Function()? _loader;
  AdConfig? _cached;

  @override
  Future<AdConfig> getConfig() async {
    final loaded = _loader == null ? _fallback : await _loader();
    final json = loaded.isEmpty ? _fallback : loaded;
    return _cached ??= AdConfigParser().parse(json);
  }
}
