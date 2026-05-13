import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../platform/ad_registry.dart';
import '../platform/admob/admob_platform.dart';
import '../utils/ad_logger.dart';
import '../utils/ad_reporter.dart';
import 'ad_guard.dart';
import 'ad_lifecycle.dart';

class AdEngine {
  AdEngine._internal();
  static final AdEngine instance = AdEngine._internal();

  AdConfigRepository _configRepository = DefaultAdConfigRepository();
  AdEventReporter _reporter = DefaultAdEventReporter();
  late final AdSdkInitializer _sdkInitializer;
  late final AdAdapterRegistry _adapterRegistry;
  final AdDisplayGuard _guard = AdDisplayGuard();

  late final AdLifecycle _lifecycle;

  final Map<PlacementType, PlacementAdSlot> _fullscreenSlots = {};
  final Map<PlacementType, Future<bool>> _fullscreenLoadingFutures = {};
  final Map<PlacementType, Future<bool>> _nativeLoadingFutures = {};

  final Map<PlacementType, PlacementAdSlot> _nativeSlots = {};
  final Map<PlacementType, Timer> _nativeRefreshTimers = {};

  AdConfigRepository get configRepository => _configRepository;
  Future<AdConfig> get config => _configRepository.getConfig();

  bool _initialized = false;

  Future<void> initWith({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
  }) async {
    if (_initialized) {
      return;
    }
    _configRepository = configRepository;
    _reporter = eventReporter;
    await init();
  }

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    _sdkInitializer = AdSdkInitializer([AdmobSdkInitializer()]);
    _adapterRegistry = AdAdapterRegistry([
      AdmobOpenAdapter(),
      AdmobInterstitialAdapter(),
      AdmobRewardedAdapter(),
      AdmobNativeAdapter(),
    ]);

    _lifecycle = AdLifecycle(this);

    log.d('🏁 [engine] start');
    await _sdkInitializer.initAll();
    await _configRepository.getConfig();
    _lifecycle.start();
    _initialized = true;
    log.d('🏁 [engine] ready');

    // 开屏广告比较特殊，我们需要在初始化阶段确保它开始加载（且可选地等待，但通常由 show 处理）
    // 为了保证 show(open) 时已经有加载任务，我们同步调用一次
    await preload(PlacementType.open);

    // 其他广告位根据 JSON 配置异步预加载
    unawaited(preloadStartupAds());
  }

  // --- Fullscreen Logic ---

  Future<bool> preload(PlacementType placement) async {
    if (_fullscreenLoadingFutures.containsKey(placement)) {
      log.d('📥 [preload] wait: ${placement.name}');
      return await _fullscreenLoadingFutures[placement]!;
    }

    final current = _fullscreenSlots[placement];
    if (current?.hasAd == true) {
      log.d('📥 [preload] skip: ${placement.name} (has cache)');
      return true;
    }

    log.d('📥 [preload] start: ${placement.name}');
    final loadFuture = _performFullscreenLoad(placement);
    _fullscreenLoadingFutures[placement] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      _fullscreenLoadingFutures.remove(placement);
    }
  }

  Future<bool> _performFullscreenLoad(PlacementType placement) async {
    _fullscreenSlots[placement] = PlacementAdSlot(
      placement: placement,
      isLoading: true,
    );

    try {
      final config = await _configRepository.getConfig();
      final policy = config.getPolicy(placement);
      final timeout = Duration(seconds: config.loadTimeoutSeconds);
      final units =
          config
              .getUnits(placement)
              .where((unit) => unit.isValid)
              .where((unit) => policy.supports(unit.type))
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      if (units.isEmpty) {
        log.d('📥 [preload] empty: ${placement.name}');
        _fullscreenSlots[placement] = PlacementAdSlot(placement: placement);
        return false;
      }

      log.d('📥 [preload] units=${units.length}: ${placement.name}');

      Object? lastError;
      for (final unit in units) {
        log.d(
          '📥 [preload] try: ${placement.name} type=${unit.type.name} id=${unit.id}',
        );
        _reportEvent(
          AdEventType.loadRequested,
          placement,
          unit.type,
          unit.source,
          unit.id,
        );

        final adapter = _adapterRegistry.get(unit.source, unit.type);
        final result = await adapter.load(
          placement: placement,
          unit: unit,
          timeout: timeout,
          reporter: _reporter,
          onLateAdLoaded: (ad, type, adUnitId) =>
              _handleLateAd(placement, ad, type, adUnitId, unit.source),
        );

        if (result.isSuccess) {
          _fullscreenSlots[placement] = PlacementAdSlot(
            placement: placement,
            ad: result.ad,
            loadedSource: unit.source,
            loadedType: unit.type,
            adUnitId: unit.id,
            loadedAt: DateTime.now(),
          );
          _reportEvent(
            AdEventType.loadSucceeded,
            placement,
            unit.type,
            unit.source,
            unit.id,
          );
          log.d('✅ [preload] success: ${placement.name} (${unit.type.name})');
          return true;
        }

        lastError = result.error;
        log.d(
          '❌ [preload] fail: ${placement.name} (${unit.type.name}) error=$lastError',
        );
        _reportEvent(
          AdEventType.loadFailed,
          placement,
          unit.type,
          unit.source,
          unit.id,
          errorReason: lastError?.toString(),
        );
      }

      log.d('❌ [preload] exhausted: ${placement.name}');
      _fullscreenSlots[placement] = PlacementAdSlot(
        placement: placement,
        lastError: lastError,
      );
      return false;
    } catch (e) {
      log.e('❌ [preload] fatal: ${placement.name} error=$e');
      _fullscreenSlots[placement] = PlacementAdSlot(
        placement: placement,
        lastError: e,
      );
      return false;
    }
  }

  void _handleLateAd(
    PlacementType placement,
    Object ad,
    AdType type,
    String adUnitId,
    AdSource source,
  ) {
    final slots = type == AdType.native ? _nativeSlots : _fullscreenSlots;
    final current = slots[placement];
    if (current?.hasAd == true) {
      log.d('📥 [late_load] discard: ${placement.name}');
      _adapterRegistry.get(source, type).dispose(ad);
      return;
    }

    log.d('📥 [late_load] accept: ${placement.name} ($adUnitId)');
    slots[placement] = PlacementAdSlot(
      placement: placement,
      ad: ad,
      loadedSource: source,
      loadedType: type,
      adUnitId: adUnitId,
      loadedAt: DateTime.now(),
    );
  }

  Future<bool> show(
    PlacementType placement, {
    String? placementLabel,
    VoidCallback? onAdShowed,
  }) async {
    final placementValue = placementLabel ?? placement.name;
    log.d('🚀 [show] request: $placementValue');

    final guardResult = await _guard.canShow(
      placement: placement,
      configRepository: _configRepository,
    );
    if (!guardResult.allowed) {
      log.d(
        '🚫 [show] blocked: $placementValue reason=${guardResult.reason?.name}',
      );
      _reportEvent(
        AdEventType.blockedByGuard,
        placement,
        AdType.interstitial,
        AdSource.admob,
        '',
        errorReason: guardResult.reason?.name,
      );
      return false;
    }

    if (!(_fullscreenSlots[placement]?.hasAd ?? false)) {
      log.d('📥 [show] no_cache, try_preload');
      await preload(placement);
    }

    final adConfig = await config;
    final policy = adConfig.getPolicy(placement);
    final slot = _fullscreenSlots[placement];

    if (slot == null || slot.ad == null) {
      log.d('❌ [show] failed: no_cache');
      if (policy.showNotReadyToast) {
        SmartDialog.showToast(
          policy.notReadyMsg ?? 'The ad is not ready, please try again later.',
        );
      }
      return false;
    }

    _guard.markShowStarted(placement, policy);
    final adapter = _adapterRegistry.get(slot.loadedSource!, slot.loadedType!);
    final result = await adapter.show(
      placement: placement,
      placementLabel: placementLabel,
      ad: slot.ad!,
      reporter: _reporter,
      onAdShowed: onAdShowed,
      onClosed: () {
        _fullscreenSlots.remove(placement);
        unawaited(preload(placement));
      },
    );

    if (result.shown) {
      _guard.markShowCompleted(placement, policy);
    } else {
      _guard.markShowFailed(placement, policy);
      _fullscreenSlots.remove(placement);
    }
    return result.shown;
  }

  // --- Native Logic ---

  Future<bool> preloadNative(PlacementType placement) async {
    if (_nativeLoadingFutures.containsKey(placement)) {
      log.d('📥 [preload] wait: native:${placement.name}');
      return await _nativeLoadingFutures[placement]!;
    }

    final current = _nativeSlots[placement];
    if (current?.hasAd == true) {
      return true;
    }

    log.d('📥 [preload] start: native:${placement.name}');
    final loadFuture = _performNativeLoad(placement);
    _nativeLoadingFutures[placement] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      _nativeLoadingFutures.remove(placement);
    }
  }

  Future<bool> _performNativeLoad(PlacementType placement) async {
    _nativeSlots[placement] = PlacementAdSlot(
      placement: placement,
      isLoading: true,
    );

    try {
      final config = await _configRepository.getConfig();
      final policy = config.getPolicy(placement);
      final units =
          config
              .getUnits(placement)
              .where((u) => u.isValid && policy.supports(u.type))
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      for (final unit in units) {
        _reportEvent(
          AdEventType.loadRequested,
          placement,
          unit.type,
          unit.source,
          unit.id,
        );
        final adapter = _adapterRegistry.get(unit.source, unit.type);
        final result = await adapter.load(
          placement: placement,
          unit: unit,
          timeout: Duration(seconds: config.loadTimeoutSeconds),
          reporter: _reporter,
        );

        if (result.isSuccess) {
          _nativeSlots[placement] = PlacementAdSlot(
            placement: placement,
            ad: result.ad,
            loadedSource: unit.source,
            loadedType: unit.type,
            adUnitId: unit.id,
            loadedAt: DateTime.now(),
          );
          _scheduleNativeRefresh(placement, unit.refreshMinutes);
          _reportEvent(
            AdEventType.loadSucceeded,
            placement,
            unit.type,
            unit.source,
            unit.id,
          );
          return true;
        }
      }
      _nativeSlots[placement] = PlacementAdSlot(placement: placement);
      return false;
    } catch (e) {
      log.e('❌ [preload] fatal: native:${placement.name} error=$e');
      _nativeSlots[placement] = PlacementAdSlot(placement: placement);
      return false;
    }
  }

  Object? getNativeAd(PlacementType placement) => _nativeSlots[placement]?.ad;

  void _scheduleNativeRefresh(PlacementType placement, int? minutes) {
    _nativeRefreshTimers.remove(placement)?.cancel();
    _nativeRefreshTimers[placement] = Timer(
      Duration(minutes: minutes ?? 40),
      () {
        _nativeSlots.remove(placement);
        preloadNative(placement);
      },
    );
  }

  // --- Helpers ---

  void _reportEvent(
    AdEventType type,
    PlacementType p,
    AdType t,
    AdSource s,
    String id, {
    String? errorReason,
  }) {
    _reporter.report(
      AdEvent(
        eventType: type,
        placement: p,
        adType: t,
        source: s,
        adUnitId: id,
        errorReason: errorReason,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> preloadStartupAds() async {
    final c = await _configRepository.getConfig();
    final list = c.preloadList.toSet();

    for (final p in list) {
      if (p == PlacementType.open) {
        continue; // 已经在 init 中加载过了
      }
      final policy = c.getPolicy(p);
      if (policy.isFullscreen) {
        unawaited(preload(p));
      } else {
        unawaited(preloadNative(p));
      }
    }
  }
}
