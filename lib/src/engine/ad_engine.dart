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

/// 广告引擎核心控制器（单例）。
///
/// 负责：
/// - 广告预加载与缓存管理（[PlacementAdPool]）
/// - 全屏广告展示控制与 CD 守卫（[AdDisplayGuard]）
/// - 原生广告加载与自动刷新
/// - 埋点事件上报（[AdEventReporter]）
///
/// ## 多广告缓存
/// JSON 中通过 id/id2/ids 配置多个广告单元 ID 时，
/// [cacheSizeFor] 返回所有单元的 poolSize 最大值，
/// [_performFullscreenLoad] 和 [_performNativeLoad] 会循环加载直到缓存池达到目标数量。
///
/// ## show() 的 await 行为
/// [show] 会等待 adapter.show() 完成才返回，而 adapter.show()
/// 的实现保证在用户关闭广告后才 complete。因此连续两次 await show()
/// 能实现"关闭一个再弹下一个"。
class AdEngine {
  AdEngine._internal();
  static final AdEngine instance = AdEngine._internal();

  AdConfigRepository _configRepository = DefaultAdConfigRepository();
  AdEventReporter _reporter = DefaultAdEventReporter();
  late final AdSdkInitializer _sdkInitializer;
  late final AdAdapterRegistry _adapterRegistry;
  final AdDisplayGuard _guard = AdDisplayGuard();

  final Map<PlacementType, PlacementAdPool> _fullscreenPools = {};
  final Map<PlacementType, Future<bool>> _fullscreenLoadingFutures = {};
  final Map<PlacementType, Future<bool>> _nativeLoadingFutures = {};

  final Map<PlacementType, PlacementAdPool> _nativePools = {};
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

    log.d('🏁 [engine] start');
    await _sdkInitializer.initAll();
    await _configRepository.getConfig();
    _initialized = true;
    log.d('🏁 [engine] ready');

    // 广告位全部由 JSON 决定，仅预加载 preload_list 中声明的 placement。
    unawaited(preloadStartupAds());
  }

  // --- Fullscreen Logic ---

  Future<bool> preload(PlacementType placement, {String? eventName}) async {
    if (_fullscreenLoadingFutures.containsKey(placement)) {
      log.d('📥 [preload] wait: ${placement.name}');
      return await _fullscreenLoadingFutures[placement]!;
    }

    final current = _fullscreenPools[placement];
    final config = await _configRepository.getConfig();
    final targetCount = config.cacheSizeFor(placement);
    if ((current?.count ?? 0) >= targetCount) {
      log.d('📥 [preload] skip: ${placement.name} (has cache)');
      return true;
    }

    log.d('📥 [preload] start: ${placement.name}');
    final loadFuture = _performFullscreenLoad(placement, eventName: eventName);
    _fullscreenLoadingFutures[placement] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      _fullscreenLoadingFutures.remove(placement);
    }
  }

  Future<bool> _performFullscreenLoad(PlacementType placement, {String? eventName}) async {
    final currentSlots = List<PlacementAdSlot>.of(
      _fullscreenPools[placement]?.slots ?? const [],
    );
    _fullscreenPools[placement] = PlacementAdPool(
      placement: placement,
      slots: currentSlots,
      isLoading: true,
    );

    try {
      final config = await _configRepository.getConfig();
      final policy = config.getPolicy(placement);
      final targetCount = config.cacheSizeFor(placement);
      final units =
          config
              .getUnits(placement)
              .where((unit) => unit.isValid)
              .where((unit) => policy.supports(unit.type))
              .where(
                (unit) =>
                    !_hasCachedAd(placement, unit.cacheKey, native: false),
              )
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      if (units.isEmpty) {
        log.d('📥 [preload] empty: ${placement.name}');
        _fullscreenPools[placement] = PlacementAdPool(
          placement: placement,
          slots: currentSlots,
        );
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
          eventName: eventName,
        );

        final adapter = _adapterRegistry.get(unit.source, unit.type);
        final result = await adapter.load(
          placement: placement,
          unit: unit,
          timeout: config.loadTimeoutFor(unit),
          reporter: _reporter,
          eventName: eventName,
          onLateAdLoaded: (ad, type, adUnitId) => unawaited(
            _handleLateAd(
              placement,
              ad,
              type,
              adUnitId,
              unit.cacheKey,
              unit.source,
            ),
          ),
        );

        if (result.isSuccess) {
          final loadedSlot = PlacementAdSlot(
            placement: placement,
            ad: result.ad,
            loadedSource: unit.source,
            loadedType: unit.type,
            adUnitId: unit.id,
            cacheKey: unit.cacheKey,
            loadedAt: DateTime.now(),
          );
          currentSlots.add(loadedSlot);
          _fullscreenPools[placement] = PlacementAdPool(
            placement: placement,
            slots: List.unmodifiable(currentSlots),
          );
          _reportEvent(
            AdEventType.loadSucceeded,
            placement,
            unit.type,
            unit.source,
            unit.id,
            eventName: eventName,
          );
          log.d(
            '✅ [preload] success: ${placement.name} '
            '(${unit.type.name}) cached=${currentSlots.length}/$targetCount',
          );
          if (currentSlots.length >= targetCount) {
            return true;
          }
          continue;
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
          eventName: eventName,
        );
      }

      log.d('❌ [preload] exhausted: ${placement.name}');
      _fullscreenPools[placement] = PlacementAdPool(
        placement: placement,
        slots: List.unmodifiable(currentSlots),
        lastError: lastError,
      );
      return currentSlots.isNotEmpty;
    } catch (e) {
      log.e('❌ [preload] fatal: ${placement.name} error=$e');
      _fullscreenPools[placement] = PlacementAdPool(
        placement: placement,
        slots: currentSlots,
        lastError: e,
      );
      return currentSlots.isNotEmpty;
    }
  }

  Future<void> _handleLateAd(
    PlacementType placement,
    Object ad,
    AdType type,
    String adUnitId,
    String cacheKey,
    AdSource source,
  ) async {
    final config = await _configRepository.getConfig();
    final targetCount = config.cacheSizeFor(placement);
    final pools = type == AdType.native ? _nativePools : _fullscreenPools;
    final current = pools[placement];
    final hasSameAd =
        current?.slots.any((slot) => slot.cacheKey == cacheKey) == true;
    if (hasSameAd || (current?.count ?? 0) >= targetCount) {
      log.d('📥 [late_load] discard: ${placement.name}');
      _adapterRegistry.get(source, type).dispose(ad);
      return;
    }

    log.d('📥 [late_load] accept: ${placement.name} ($adUnitId)');
    final slots = List<PlacementAdSlot>.of(current?.slots ?? const [])
      ..add(
        PlacementAdSlot(
          placement: placement,
          ad: ad,
          loadedSource: source,
          loadedType: type,
          adUnitId: adUnitId,
          cacheKey: cacheKey,
          loadedAt: DateTime.now(),
        ),
      );
    pools[placement] = PlacementAdPool(
      placement: placement,
      slots: List.unmodifiable(slots),
    );
  }

  Future<bool> show(
    PlacementType placement, {
    String? placementLabel,
    String? eventName,
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
        eventName: eventName,
      );
      return false;
    }

    if (!(_fullscreenPools[placement]?.hasAd ?? false)) {
      log.d('📥 [show] no_cache, try_preload');
      await preload(placement, eventName: eventName);
    }

    final adConfig = await config;
    final policy = adConfig.getPolicy(placement);
    final pool = _fullscreenPools[placement];
    final slot = pool?.slots.isEmpty == false ? pool!.slots.first : null;

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
      eventName: eventName,
      ad: slot.ad!,
      reporter: _reporter,
      onAdShowed: onAdShowed,
      onClosed: () {
        _removeCachedAd(placement, slot, native: false);
        unawaited(preload(placement));
      },
    );

    if (result.shown) {
      _guard.markShowCompleted(placement, policy);
    } else {
      _guard.markShowFailed(placement, policy);
      _removeCachedAd(placement, slot, native: false);
    }
    return result.shown;
  }

  // --- Native Logic ---

  Future<bool> preloadNative(PlacementType placement, {String? eventName}) async {
    if (_nativeLoadingFutures.containsKey(placement)) {
      log.d('📥 [preload] wait: native:${placement.name}');
      return await _nativeLoadingFutures[placement]!;
    }

    final current = _nativePools[placement];
    final config = await _configRepository.getConfig();
    final targetCount = config.cacheSizeFor(placement);
    if ((current?.count ?? 0) >= targetCount) {
      return true;
    }

    log.d('📥 [preload] start: native:${placement.name}');
    final loadFuture = _performNativeLoad(placement, eventName: eventName);
    _nativeLoadingFutures[placement] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      _nativeLoadingFutures.remove(placement);
    }
  }

  Future<bool> _performNativeLoad(PlacementType placement, {String? eventName}) async {
    final currentSlots = List<PlacementAdSlot>.of(
      _nativePools[placement]?.slots ?? const [],
    );
    _nativePools[placement] = PlacementAdPool(
      placement: placement,
      slots: currentSlots,
      isLoading: true,
    );

    try {
      final config = await _configRepository.getConfig();
      final policy = config.getPolicy(placement);
      final targetCount = config.cacheSizeFor(placement);
      final units =
          config
              .getUnits(placement)
              .where((u) => u.isValid && policy.supports(u.type))
              .where((u) => !_hasCachedAd(placement, u.cacheKey, native: true))
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      for (final unit in units) {
        _reportEvent(
          AdEventType.loadRequested,
          placement,
          unit.type,
          unit.source,
          unit.id,
          eventName: eventName,
        );
        final adapter = _adapterRegistry.get(unit.source, unit.type);
        final result = await adapter.load(
          placement: placement,
          unit: unit,
          timeout: config.loadTimeoutFor(unit),
          reporter: _reporter,
          eventName: eventName,
          onLateAdLoaded: (ad, type, adUnitId) => unawaited(
            _handleLateAd(
              placement,
              ad,
              type,
              adUnitId,
              unit.cacheKey,
              unit.source,
            ),
          ),
        );

        if (result.isSuccess) {
          final loadedSlot = PlacementAdSlot(
            placement: placement,
            ad: result.ad,
            loadedSource: unit.source,
            loadedType: unit.type,
            adUnitId: unit.id,
            cacheKey: unit.cacheKey,
            loadedAt: DateTime.now(),
          );
          currentSlots.add(loadedSlot);
          _nativePools[placement] = PlacementAdPool(
            placement: placement,
            slots: List.unmodifiable(currentSlots),
          );
          _scheduleNativeRefresh(placement, unit.refreshMinutes);
          _reportEvent(
            AdEventType.loadSucceeded,
            placement,
            unit.type,
            unit.source,
            unit.id,
            eventName: eventName,
          );
          if (currentSlots.length >= targetCount) {
            return true;
          }
        }
      }
      _nativePools[placement] = PlacementAdPool(
        placement: placement,
        slots: List.unmodifiable(currentSlots),
      );
      return currentSlots.isNotEmpty;
    } catch (e) {
      log.e('❌ [preload] fatal: native:${placement.name} error=$e');
      _nativePools[placement] = PlacementAdPool(
        placement: placement,
        slots: currentSlots,
        lastError: e,
      );
      return currentSlots.isNotEmpty;
    }
  }

  Object? getNativeAd(PlacementType placement) =>
      _nativePools[placement]?.firstAd;

  List<Object> getNativeAds(PlacementType placement, {int count = 2}) {
    return _nativePools[placement]?.ads.take(count).toList() ?? const [];
  }

  void _scheduleNativeRefresh(PlacementType placement, int? minutes) {
    _nativeRefreshTimers.remove(placement)?.cancel();
    _nativeRefreshTimers[placement] = Timer(
      Duration(minutes: minutes ?? 40),
      () {
        _nativePools.remove(placement);
        preloadNative(placement);
      },
    );
  }

  // --- Helpers ---

  bool _hasCachedAd(
    PlacementType placement,
    String cacheKey, {
    required bool native,
  }) {
    final pool = native ? _nativePools[placement] : _fullscreenPools[placement];
    return pool?.slots.any((slot) => slot.cacheKey == cacheKey) == true;
  }

  void _removeCachedAd(
    PlacementType placement,
    PlacementAdSlot slot, {
    required bool native,
  }) {
    final pools = native ? _nativePools : _fullscreenPools;
    final current = pools[placement];
    if (current == null) {
      return;
    }

    final slots = current.slots
        .where((item) => !identical(item.ad, slot.ad))
        .toList();
    if (slots.isEmpty) {
      pools.remove(placement);
      return;
    }

    pools[placement] = PlacementAdPool(
      placement: placement,
      slots: List.unmodifiable(slots),
    );
  }

  void _reportEvent(
    AdEventType type,
    PlacementType p,
    AdType t,
    AdSource s,
    String id, {
    String? errorReason,
    String? eventName,
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
        eventName: eventName,
      ),
    );
  }

  Future<void> preloadStartupAds() async {
    final c = await _configRepository.getConfig();
    final list = c.preloadList.toSet();

    for (final p in list) {
      final policy = c.getPolicy(p);
      if (policy.isFullscreen) {
        unawaited(preload(p));
      } else {
        unawaited(preloadNative(p));
      }
    }
  }
}
