import 'package:flutter/widgets.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../core/ad_policy.dart';
import '../engine/ad_cache_service.dart';
import '../engine/ad_event_mapper.dart';
import '../engine/ad_guard.dart';
import '../engine/ad_loader_service.dart';
import '../engine/ad_presenter.dart';
import '../platform/ad_adapter.dart';
import '../platform/ad_registry.dart';
import '../platform/admob/admob_platform.dart';
import '../reporting/ad_health_metrics.dart';
import '../utils/ad_logger.dart';
import '../utils/ad_reporter.dart';
import 'ad_widget_factory.dart';
import 'fullscreen_native_presenter.dart';

/// Immutable configuration for [AdPlugin].
///
/// Provides all dependencies that the plugin needs at initialization.
///
/// ---
/// [AdPlugin] 的不可变配置，提供初始化所需的所有依赖。
class AdPluginConfig {
  final AdConfigRepository configRepository;
  final AdEventReporter eventReporter;
  final Map<PlacementType, PlacementPolicy> placementPolicies;
  final AdNotReadyCallback? onAdNotReady;
  final List<AdTypeAdapter>? adapters;
  final List<AdSourceSdkInitializer>? sdkInitializers;
  final int nativeAdCloseClickPercent;
  final FullscreenNativeAdPresenter? fullscreenNativePresenter;
  final bool verboseLogging;
  final bool enableHealthMetrics;

  const AdPluginConfig({
    required this.configRepository,
    required this.eventReporter,
    this.placementPolicies = const {},
    this.onAdNotReady,
    this.adapters,
    this.sdkInitializers,
    this.nativeAdCloseClickPercent = 0,
    this.fullscreenNativePresenter,
    this.verboseLogging = false,
    this.enableHealthMetrics = false,
  });
}

/// Main entry point for the ad plugin (instance-based).
///
/// Replaces the old all-static [FlutterAdPlugin]. Create one instance per
/// independent ad configuration. Call [init] before use, [dispose] when done.
///
/// ## Usage
/// ```dart
/// final plugin = AdPlugin(config: AdPluginConfig(
///   configRepository: MyConfigRepo(),
///   eventReporter: MyReporter(),
/// ));
/// await plugin.init();
/// await plugin.show(placement, context: context, eventName: 'open');
/// await plugin.dispose();
/// ```
///
/// ---
/// 广告插件入口（实例化），替代旧的全局静态 [FlutterAdPlugin]。
/// 每个独立广告配置创建一个实例。使用前调用 [init]，结束后调用 [dispose]。
class AdPlugin {
  final AdPluginConfig _config;
  late final AdWidgetFactory _widgetFactory;
  late final AdAdapterRegistry _adapterRegistry;
  late final AdCacheService _cache;
  late final AdDisplayGuard _guard;
  late final AdLoaderService _loader;
  late final AdPresenter _presenter;
  AdHealthMetrics? _healthMetrics;

  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initializing;

  AdPlugin({required AdPluginConfig config}) : _config = config;

  /// Whether the plugin has been initialized.
  bool get isInitialized => _initialized;

  /// Widget factory for rendering ads. Available after [init].
  AdWidgetFactory get widgetFactory {
    _assertInitialized();
    return _widgetFactory;
  }

  /// Health metrics aggregator. Available after [init] if enabled.
  AdHealthMetrics? get healthMetrics {
    _assertInitialized();
    return _healthMetrics;
  }

  /// Initializes the plugin. Must be called before any other method.
  ///
  /// Can be called multiple times safely (subsequent calls are no-ops).
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
    final logger = AppLogger(verboseEnabled: _config.verboseLogging);
    final sdkInitializer = AdSdkInitializer(
      _config.sdkInitializers ?? [AdmobSdkInitializer()],
    );
    final adapterRegistry = AdAdapterRegistry(
      _config.adapters ??
          [
            AdmobOpenAdapter(logger: logger),
            AdmobInterstitialAdapter(logger: logger),
            AdmobRewardedAdapter(logger: logger),
            AdmobRewardedInterstitialAdapter(logger: logger),
            AdmobNativeAdapter(logger: logger),
            AdmobBannerAdapter(logger: logger),
          ],
    );
    final cache = AdCacheService();
    final guard = AdDisplayGuard();
    final eventMapper = AdEventMapper();
    final healthMetrics = _config.enableHealthMetrics
        ? AdHealthMetrics()
        : null;
    final widgetFactory = AdWidgetFactory();

    // Build config repository with policy overrides
    final effectiveConfigRepo = _config.placementPolicies.isEmpty
        ? _config.configRepository
        : _PolicyOverrideRepo(
            _config.configRepository,
            _config.placementPolicies,
          );

    final loader = AdLoaderService(
      configRepository: effectiveConfigRepo,
      adapterRegistry: adapterRegistry,
      cache: cache,
      eventMapper: eventMapper,
      reporter: _config.eventReporter,
      logger: logger,
    );

    final presenter = AdPresenter(
      configRepository: effectiveConfigRepo,
      adapterRegistry: adapterRegistry,
      cache: cache,
      guard: guard,
      eventMapper: eventMapper,
      reporter: _config.eventReporter,
      loader: loader,
      logger: logger,
      fullscreenNativePresenter: _config.fullscreenNativePresenter,
    );

    await sdkInitializer.initAll();

    // Prime config
    await effectiveConfigRepo.getConfig();

    if (_disposed) {
      loader.dispose();
      return;
    }

    _adapterRegistry = adapterRegistry;
    _cache = cache;
    _guard = guard;
    _loader = loader;
    _presenter = presenter;
    _healthMetrics = healthMetrics;
    _widgetFactory = widgetFactory;
    _initialized = true;
  }

  /// Disposes all resources: timers, caches, in-flight loads.
  ///
  /// After calling [dispose], the instance cannot be reused.
  /// Create a new [AdPlugin] if needed.
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
      _adapterRegistry.tryGet(slot.source, slot.type)?.dispose(slot.ad);
    }
    _guard.resetForTesting();
    _initialized = false;
  }

  // --- Fullscreen ---

  Future<bool> preload(PlacementType placement, {required String eventName}) {
    _assertInitialized();
    return _loader.preload(placement, eventName: eventName);
  }

  Future<void> preloadPlacements(
    Iterable<PlacementType> placements, {
    required String eventName,
  }) {
    _assertInitialized();
    return _loader.preloadPlacements(placements, eventName: eventName);
  }

  Future<AdShowResult> show(
    PlacementType placement, {
    BuildContext? context,
    required String eventName,
    int? closePassThroughPercent,
  }) {
    _assertInitialized();
    return _presenter.show(
      placement,
      context: context,
      eventName: eventName,
      closePassThroughPercent:
          closePassThroughPercent ?? _config.nativeAdCloseClickPercent,
      onAdNotReady: _config.onAdNotReady,
    );
  }

  Future<AdSequenceShowResult> showSequence(
    PlacementType placement, {
    BuildContext? context,
    required String eventName,
    int? closePassThroughPercent,
  }) {
    _assertInitialized();
    return _presenter.showSequence(
      placement,
      context: context,
      eventName: eventName,
      closePassThroughPercent:
          closePassThroughPercent ?? _config.nativeAdCloseClickPercent,
      onAdNotReady: _config.onAdNotReady,
    );
  }

  // --- Native ---

  Future<bool> loadNative(
    PlacementType placement, {
    required String eventName,
    String? cacheId,
  }) {
    _assertInitialized();
    return _loader.preloadNative(
      placement,
      eventName: eventName,
      cacheId: cacheId,
    );
  }

  Object? getNativeAd(
    PlacementType placement, {
    String? cacheId,
    required String eventName,
  }) {
    _assertInitialized();
    return _presenter.getNativeAd(
      placement,
      cacheId: cacheId,
      eventName: eventName,
    );
  }

  List<Object> getNativeAds(
    PlacementType placement, {
    int count = 2,
    String? cacheId,
    required String eventName,
  }) {
    _assertInitialized();
    return _presenter.getNativeAds(
      placement,
      count: count,
      cacheId: cacheId,
      eventName: eventName,
    );
  }

  // --- Banner ---

  Future<bool> loadBanner(
    PlacementType placement, {
    required String eventName,
  }) {
    _assertInitialized();
    return _loader.preloadBanner(placement, eventName: eventName);
  }

  Object? getBannerAd(PlacementType placement, {required String eventName}) {
    _assertInitialized();
    return _presenter.getBannerAd(placement, eventName: eventName);
  }

  List<Object> getBannerAds(
    PlacementType placement, {
    int count = 2,
    required String eventName,
  }) {
    _assertInitialized();
    return _presenter.getBannerAds(
      placement,
      count: count,
      eventName: eventName,
    );
  }

  void disposeBannerAd(PlacementType placement) {
    _assertInitialized();
    _presenter.disposeBannerAd(placement);
  }

  void disposeNativeAd(PlacementType placement, {String? cacheId}) {
    _assertInitialized();
    _presenter.disposeNativeAd(placement, cacheId: cacheId);
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError('AdPlugin not initialized. Call init() first.');
    }
  }
}

/// Internal config repository that merges host-provided placement policies
/// into the parsed [AdConfig].
class _PolicyOverrideRepo implements AdConfigRepository {
  _PolicyOverrideRepo(this._delegate, this._policies);

  final AdConfigRepository _delegate;
  final Map<PlacementType, PlacementPolicy> _policies;
  AdConfig? _cached;

  @override
  Future<AdConfig> getConfig() async {
    return _cached ??= _withPolicies(await _delegate.getConfig());
  }

  AdConfig _withPolicies(AdConfig config) {
    return AdConfig(
      loadTimeoutSeconds: config.loadTimeoutSeconds,
      rewardedLoadTimeoutSeconds: config.rewardedLoadTimeoutSeconds,
      adCdSeconds: config.adCdSeconds,
      commonPlacements: config.commonPlacements,
      highValuePlacement: config.highValuePlacement,
      placements: config.placements,
      policies: _policies,
    );
  }
}
