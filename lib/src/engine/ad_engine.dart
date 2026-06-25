import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../platform/ad_adapter.dart';
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
  AdNotReadyCallback? _onAdNotReady;
  AdSdkInitializer? _sdkInitializer;
  AdAdapterRegistry? _adapterRegistry;
  int _nativeAdCloseClickPercent = 0;
  AdFullScreenNativeStyle _fullScreenNativeStyle =
      const AdFullScreenNativeStyle();
  final AdDisplayGuard _guard = AdDisplayGuard();

  _AdPoolStore _fullscreenPool = _AdPoolStore();
  final Map<PlacementType, Future<bool>> _fullscreenLoadingFutures = {};
  final Map<PlacementType, Future<bool>> _nativeLoadingFutures = {};

  _AdPoolStore _nativePool = _AdPoolStore();
  final Map<PlacementType, Timer> _nativeRefreshTimers = {};

  AdConfigRepository get configRepository => _configRepository;
  Future<AdConfig> get config => _configRepository.getConfig();

  bool _initialized = false;

  Future<void> initWith({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
    Map<PlacementType, PlacementPolicy> placementPolicies = const {},
    AdNotReadyCallback? onAdNotReady,
    List<AdTypeAdapter>? adapters,
    List<AdSourceSdkInitializer>? sdkInitializers,
    int nativeAdCloseClickPercent = 0,
    AdFullScreenNativeStyle fullScreenNativeStyle =
        const AdFullScreenNativeStyle(),
  }) async {
    if (_initialized) {
      return;
    }
    _configRepository = placementPolicies.isEmpty
        ? configRepository
        : _PolicyOverrideConfigRepository(configRepository, placementPolicies);
    _reporter = eventReporter;
    _onAdNotReady = onAdNotReady;
    _nativeAdCloseClickPercent = nativeAdCloseClickPercent.clamp(0, 100);
    _fullScreenNativeStyle = fullScreenNativeStyle;
    await init(adapters: adapters, sdkInitializers: sdkInitializers);
  }

  Future<void> init({
    List<AdTypeAdapter>? adapters,
    List<AdSourceSdkInitializer>? sdkInitializers,
  }) async {
    if (_initialized) {
      return;
    }

    _sdkInitializer = AdSdkInitializer(
      sdkInitializers ?? [AdmobSdkInitializer()],
    );
    _adapterRegistry = AdAdapterRegistry(
      adapters ??
          [
            AdmobOpenAdapter(),
            AdmobInterstitialAdapter(),
            AdmobRewardedAdapter(),
            AdmobNativeAdapter(),
          ],
    );

    await _sdkInitializer!.initAll();
    await _configRepository.getConfig();
    _initialized = true;
  }

  @visibleForTesting
  static void resetForTesting() {
    instance._initialized = false;
    instance._sdkInitializer = null;
    instance._adapterRegistry = null;
    instance._nativeAdCloseClickPercent = 0;
    instance._fullScreenNativeStyle = const AdFullScreenNativeStyle();
    instance._fullscreenPool = _AdPoolStore();
    instance._fullscreenLoadingFutures.clear();
    instance._nativeLoadingFutures.clear();
    instance._nativePool = _AdPoolStore();
    instance._nativeRefreshTimers.forEach((_, timer) => timer.cancel());
    instance._nativeRefreshTimers.clear();
    instance._guard.resetForTesting();
  }

  // --- Fullscreen Logic ---

  Future<bool> preload(
    PlacementType placement, {
    required String eventName,
  }) async {
    final config = await _configRepository.getConfig();
    if (!config.hasPlacement(placement)) {
      var loaded = false;
      for (final common in config.commonPlacements) {
        loaded = await preload(common, eventName: eventName) || loaded;
      }
      return loaded;
    }

    if (_fullscreenLoadingFutures.containsKey(placement)) {
      return await _fullscreenLoadingFutures[placement]!;
    }

    final current = _fullscreenPool[placement];
    final targetCount = config.fullscreenCacheSizeFor(placement);
    if ((current?.count ?? 0) >= targetCount) {
      return true;
    }

    final loadFuture = _performFullscreenLoad(placement, eventName: eventName);
    _fullscreenLoadingFutures[placement] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      _fullscreenLoadingFutures.remove(placement);
    }
  }

  Future<bool> _performFullscreenLoad(
    PlacementType placement, {
    required String eventName,
  }) {
    return _performLoad(
      placement: placement,
      eventName: eventName,
      kind: _AdLoadKind.fullscreen,
      pool: _fullscreenPool,
      targetCountFor: (config) => config.fullscreenCacheSizeFor(placement),
      unitsFor: (config) {
        final policy = config.getPolicy(placement);
        return config
            .getUnits(placement)
            .where((unit) => unit.isValid)
            .where((unit) => policy.supports(unit.type))
            .where(
              (unit) =>
                  unit.type.isFullscreen ||
                  (policy.isFullscreen && unit.type == AdType.native),
            )
            .where(
              (unit) => !_fullscreenPool.hasCacheKey(placement, unit.cacheKey),
            );
      },
      adapterTypeFor: (unit) => unit.type.isNative ? AdType.native : unit.type,
      loadedTypeFor: (unit) => unit.type.isNative ? AdType.native : unit.type,
    );
  }

  Future<void> _handleLateAd(
    PlacementType placement,
    Object ad,
    AdType type,
    String adUnitId,
    String cacheKey,
    AdSource source,
    _AdLoadKind kind,
  ) async {
    final config = await _configRepository.getConfig();
    final targetCount = kind == _AdLoadKind.native
        ? config.nativeCacheSizeFor(placement)
        : config.fullscreenCacheSizeFor(placement);
    final pool = kind == _AdLoadKind.native ? _nativePool : _fullscreenPool;
    final current = pool[placement];
    final hasSameAd = pool.hasCacheKey(placement, cacheKey);
    if (hasSameAd || (current?.count ?? 0) >= targetCount) {
      _adapterRegistry!.get(source, type).dispose(ad);
      return;
    }

    pool.add(
      placement,
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
  }

  Future<bool> show(
    PlacementType placement, {
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
  }) async {
    final showContext = _AdShowContext(context);
    final placementValue = placementLabel ?? placement.name;
    final adConfig = await config;
    final requestPlacement = placement;
    final showPlacement = _resolveShowPlacement(adConfig, requestPlacement);
    final isFallbackPlacement = showPlacement != requestPlacement;
    final policy = adConfig.getPolicy(showPlacement);
    final preferHighValue =
        !isFallbackPlacement && policy.preferHighValueOnShow;
    log.v(
      '🚀 [show] request: request=${requestPlacement.name} '
      'label=$placementValue show=${showPlacement.name} '
      'commonResolved=$isFallbackPlacement '
      'event=$eventName waitForLoad=${policy.waitForLoadOnShow}',
    );

    final guardResult = await _guard.canShow(
      placement: showPlacement,
      configRepository: _configRepository,
    );
    if (!guardResult.allowed) {
      log.v(
        '🚫 [show] blocked: $placementValue reason=${guardResult.reason?.name}',
      );
      _reportShowFail(
        adConfig: adConfig,
        placement: showPlacement,
        eventName: eventName,
        errorReason: 'guard_blocked: ${guardResult.reason?.name ?? "unknown"}',
      );
      return false;
    }

    if (!_fullscreenPool.hasAd(showPlacement)) {
      if (policy.waitForLoadOnShow) {
        log.v(
          '📥 [show] no_cache, try_preload: placement=${showPlacement.name} '
          'event=$eventName',
        );
        await preload(showPlacement, eventName: eventName);
      } else {
        log.v(
          '📥 [show] no_cache, skip_wait: placement=${showPlacement.name} '
          'event=$eventName',
        );
      }
    }

    final slot = _selectShowSlot(
      config: adConfig,
      requestedPlacement: requestPlacement,
      showPlacement: showPlacement,
      preferHighValue: preferHighValue,
    );

    if (slot == null || slot.ad == null) {
      log.v(
        '❌ [show] failed: reason=no_cache request=${requestPlacement.name} '
        'show=${showPlacement.name}',
      );
      _reportShowFail(
        adConfig: adConfig,
        placement: showPlacement,
        eventName: eventName,
        errorReason: 'no_cache',
      );
      if (policy.showNotReadyToast && _onAdNotReady != null) {
        _onAdNotReady!(
          AdNotReadyEvent(
            requestedPlacement: requestPlacement,
            showPlacement: showPlacement,
            placementLabel: placementLabel,
            eventName: eventName,
            message:
                policy.notReadyMsg ??
                'The ad is not ready, please try again later.',
          ),
        );
      }
      return false;
    }

    return _showSlot(
      slot: slot,
      showContext: showContext,
      reportPlacement: showPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
  }

  Future<bool> showSequence(
    PlacementType placement, {
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
  }) async {
    final showContext = _AdShowContext(context);
    final adConfig = await config;
    final showPlacement = _resolveShowPlacement(adConfig, placement);
    final policy = adConfig.getPolicy(showPlacement);

    if (!_fullscreenPool.hasAd(showPlacement) && policy.waitForLoadOnShow) {
      await preload(showPlacement, eventName: eventName);
    }

    final firstSlot = _selectShowSlot(
      config: adConfig,
      requestedPlacement: placement,
      showPlacement: showPlacement,
      preferHighValue: showPlacement != placement,
    );
    if (firstSlot == null) {
      return false;
    }

    final secondSlot = _selectShowSlot(
      config: adConfig,
      requestedPlacement: placement,
      showPlacement: showPlacement,
      excludedSlots: {firstSlot},
      preferHighValue: showPlacement != placement,
    );

    if (secondSlot == null) {
      log.v(
        '📥 [show_sequence] missing second slot: placement=${showPlacement.name} '
        'event=$eventName',
      );
      final refillFuture = preload(showPlacement, eventName: eventName);
      final firstShown = await _showSlot(
        slot: firstSlot,
        showContext: showContext,
        reportPlacement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        onAdShowed: onAdShowed,
        closePassThroughPercent: closePassThroughPercent,
      );
      if (!firstShown) {
        return false;
      }
      await refillFuture;
      final refilledSlot = _selectShowSlot(
        config: await config,
        requestedPlacement: placement,
        showPlacement: showPlacement,
        preferHighValue: showPlacement != placement,
      );
      if (refilledSlot == null) {
        return true;
      }
      await _showSlot(
        slot: refilledSlot,
        showContext: showContext,
        reportPlacement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        onAdShowed: onAdShowed,
        closePassThroughPercent: closePassThroughPercent,
      );
      return true;
    }

    final firstShown = await _showSlot(
      slot: firstSlot,
      showContext: showContext,
      reportPlacement: showPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
    if (!firstShown) {
      return false;
    }
    return _showSlot(
      slot: secondSlot,
      showContext: showContext,
      reportPlacement: showPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
  }

  // --- Native Logic ---

  Future<bool> preloadNative(
    PlacementType placement, {
    required String eventName,
  }) async {
    final config = await _configRepository.getConfig();
    if (!config.hasPlacement(placement)) {
      var loaded = false;
      for (final common in config.commonPlacements) {
        loaded = await preloadNative(common, eventName: eventName) || loaded;
      }
      return loaded;
    }

    if (_nativeLoadingFutures.containsKey(placement)) {
      return await _nativeLoadingFutures[placement]!;
    }

    final current = _nativePool[placement];
    final targetCount = config.nativeCacheSizeFor(placement);
    if ((current?.count ?? 0) >= targetCount) {
      return true;
    }

    final loadFuture = _performNativeLoad(placement, eventName: eventName);
    _nativeLoadingFutures[placement] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      _nativeLoadingFutures.remove(placement);
    }
  }

  Future<bool> _performNativeLoad(
    PlacementType placement, {
    required String eventName,
  }) {
    return _performLoad(
      placement: placement,
      eventName: eventName,
      kind: _AdLoadKind.native,
      pool: _nativePool,
      targetCountFor: (config) => config.cacheSizeFor(placement),
      unitsFor: (config) {
        final policy = config.getPolicy(placement);
        return config
            .getUnits(placement)
            .where((unit) => unit.isValid && policy.supports(unit.type))
            .where((unit) => !policy.isFullscreen || unit.type.isDoubleNative)
            .where((unit) => unit.type.isNative)
            .where(
              (unit) => !_nativePool.hasCacheKey(placement, unit.cacheKey),
            );
      },
      adapterTypeFor: (_) => AdType.native,
      loadedTypeFor: (_) => AdType.native,
      onLoaded: (unit) {
        _scheduleNativeRefresh(
          placement,
          unit.refreshMinutes,
          eventName: eventName,
        );
      },
    );
  }

  Future<bool> _performLoad({
    required PlacementType placement,
    required String eventName,
    required _AdLoadKind kind,
    required _AdPoolStore pool,
    required int Function(AdConfig config) targetCountFor,
    required Iterable<AdUnitConfig> Function(AdConfig config) unitsFor,
    required AdType Function(AdUnitConfig unit) adapterTypeFor,
    required AdType Function(AdUnitConfig unit) loadedTypeFor,
    void Function(AdUnitConfig unit)? onLoaded,
  }) async {
    final currentSlots = pool.beginLoading(placement);

    AdUnitConfig? currentUnit;

    try {
      final config = await _configRepository.getConfig();
      final targetCount = targetCountFor(config);
      final units = unitsFor(config).toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));

      if (units.isEmpty) {
        log.v(
          '📥 [preload] exhausted: placement=${placement.name} '
          'kind=${kind.name} reason=no_units event=$eventName',
        );
        pool.setSlots(placement, currentSlots);
        return false;
      }

      Object? lastError;
      for (final unit in units) {
        currentUnit = unit;
        _reportEvent(
          AdEventType.loadRequested,
          placement,
          unit.type,
          unit.source,
          unit.id,
          eventName: eventName,
        );

        final adapterType = adapterTypeFor(unit);
        final result = await _adapterRegistry!
            .get(unit.source, adapterType)
            .load(
              placement: placement,
              unit: unit,
              timeout: config.loadTimeoutFor(unit),
              reporter: _reporter,
              eventName: eventName,
              renderAsFullscreen:
                  kind == _AdLoadKind.fullscreen && unit.type.isNative,
              onLateAdLoaded: (ad, type, adUnitId) => unawaited(
                _handleLateAd(
                  placement,
                  ad,
                  type,
                  adUnitId,
                  unit.cacheKey,
                  unit.source,
                  kind,
                ),
              ),
            );

        if (result.isSuccess) {
          currentSlots.add(
            PlacementAdSlot(
              placement: placement,
              ad: result.ad,
              loadedSource: unit.source,
              loadedType: loadedTypeFor(unit),
              adUnitId: unit.id,
              cacheKey: unit.cacheKey,
              loadedAt: DateTime.now(),
            ),
          );
          pool.setSlots(placement, currentSlots);
          onLoaded?.call(unit);
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
          continue;
        }

        lastError = result.error;
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

      pool.setSlots(placement, currentSlots, lastError: lastError);
      if (currentSlots.isEmpty) {
        log.v(
          '❌ [preload] exhausted: placement=${placement.name} '
          'kind=${kind.name} event=$eventName lastError=$lastError',
        );
      }
      return currentSlots.isNotEmpty;
    } catch (e) {
      log.e(
        '❌ [preload] fatal: placement=${placement.name} '
        'kind=${kind.name} error=$e',
      );
      if (currentUnit != null) {
        _reportEvent(
          AdEventType.loadFailed,
          placement,
          currentUnit.type,
          currentUnit.source,
          currentUnit.id,
          errorReason: e.toString(),
          eventName: eventName,
        );
      }
      pool.setSlots(placement, currentSlots, lastError: e);
      return currentSlots.isNotEmpty;
    }
  }

  Object? getNativeAd(
    PlacementType placement, {
    String? placementLabel,
    required String eventName,
  }) {
    final slot = _nativePool.slots(placement).firstOrNull;
    if (slot == null) {
      return null;
    }
    _attributeNativeSlot(
      slot,
      placement: placement,
      placementLabel: placementLabel,
      eventName: eventName,
    );
    return slot.ad;
  }

  List<Object> getNativeAds(
    PlacementType placement, {
    int count = 2,
    String? placementLabel,
    required String eventName,
  }) {
    final slots = _nativePool.slots(placement).take(count).toList();
    for (final slot in slots) {
      _attributeNativeSlot(
        slot,
        placement: placement,
        placementLabel: placementLabel,
        eventName: eventName,
      );
    }
    return slots.map((slot) => slot.ad).whereType<Object>().toList();
  }

  void _scheduleNativeRefresh(
    PlacementType placement,
    int? minutes, {
    required String eventName,
  }) {
    _nativeRefreshTimers.remove(placement)?.cancel();
    _nativeRefreshTimers[placement] = Timer(
      Duration(minutes: minutes ?? 40),
      () {
        _nativePool.remove(placement);
        preloadNative(placement, eventName: eventName);
      },
    );
  }

  // --- Helpers ---

  PlacementType _resolveShowPlacement(
    AdConfig config,
    PlacementType requestedPlacement,
  ) {
    if (config.hasPlacement(requestedPlacement)) {
      return requestedPlacement;
    }
    return config.commonPlacements.firstWhere(
      config.hasPlacement,
      orElse: () => requestedPlacement,
    );
  }

  PlacementAdSlot? _selectShowSlot({
    required AdConfig config,
    required PlacementType requestedPlacement,
    required PlacementType showPlacement,
    Set<PlacementAdSlot> excludedSlots = const {},
    required bool preferHighValue,
  }) {
    final highValuePlacement = config.highValuePlacement;
    if (preferHighValue && highValuePlacement != null) {
      final highValueSlot = _firstUsableFullscreenSlot(
        highValuePlacement,
        excludedSlots: excludedSlots,
      );
      final configuredSlots = _fullscreenPool.slots(showPlacement);
      final configuredFirst = configuredSlots.firstOrNull;
      final shouldUseHighValue =
          highValueSlot != null &&
          !(configuredFirst?.loadedType?.isNative ?? false);
      if (shouldUseHighValue) {
        return highValueSlot;
      }
    }

    return _firstUsableFullscreenSlot(
      showPlacement,
      excludedSlots: excludedSlots,
    );
  }

  PlacementAdSlot? _firstUsableFullscreenSlot(
    PlacementType placement, {
    Set<PlacementAdSlot> excludedSlots = const {},
  }) {
    final slots = _fullscreenPool.slots(placement);
    for (final slot in slots) {
      if (!excludedSlots.contains(slot) &&
          slot.ad != null &&
          ((slot.loadedType?.isFullscreen ?? false) ||
              (slot.loadedType?.isNative ?? false))) {
        return slot;
      }
    }
    return null;
  }

  Future<bool> _showSlot({
    required PlacementAdSlot slot,
    required _AdShowContext showContext,
    required PlacementType reportPlacement,
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
  }) async {
    final slotPlacement = slot.placement;
    final adConfig = await config;
    final slotPolicy = adConfig.getPolicy(slotPlacement);
    final adapter = _adapterRegistry!.get(slot.loadedSource!, slot.loadedType!);

    _guard.markShowStarted(slotPlacement, slotPolicy);
    _reportEvent(
      AdEventType.show,
      reportPlacement,
      slot.loadedType!,
      slot.loadedSource!,
      slot.adUnitId!,
      eventName: eventName,
    );
    final result = await adapter.show(
      placement: reportPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      ad: slot.ad!,
      reporter: _reporter,
      onAdShowed: onAdShowed,
      onClosed: () {
        _fullscreenPool.removeSlot(slotPlacement, slot);
        unawaited(preload(slotPlacement, eventName: eventName));
      },
      closePassThroughPercent:
          (closePassThroughPercent ?? _nativeAdCloseClickPercent).clamp(0, 100),
      context: showContext.current,
      style: _fullScreenNativeStyle,
    );
    if (result.shown) {
      _guard.markShowCompleted(slotPlacement, slotPolicy);
    } else {
      log.v(
        '❌ [show] failed: reportPlacement=${reportPlacement.name} '
        'cachePlacement=${slotPlacement.name} id=${slot.adUnitId} '
        'error=${result.error}',
      );
      _guard.markShowFailed(slotPlacement, slotPolicy);
      _fullscreenPool.removeSlot(slotPlacement, slot);
    }
    return result.shown;
  }

  void _attributeNativeSlot(
    PlacementAdSlot slot, {
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
  }) {
    final ad = slot.ad;
    if (ad == null) {
      return;
    }
    AdmobNativeAdapter.updateAttribution(
      ad: ad,
      placement: placement,
      placementLabel: placementLabel,
      eventName: eventName,
    );
  }

  void _reportEvent(
    AdEventType type,
    PlacementType p,
    AdType? t,
    AdSource? s,
    String? id, {
    String? errorReason,
    required String eventName,
  }) {
    final event = AdEvent(
      eventType: type,
      placement: p,
      adType: t,
      source: s,
      adUnitId: id,
      errorReason: errorReason,
      timestamp: DateTime.now(),
      eventName: eventName,
    );
    log.event(event);
    _reporter.report(event);
  }

  void _reportShowFail({
    required AdConfig adConfig,
    required PlacementType placement,
    required String eventName,
    required String errorReason,
  }) {
    final units = adConfig.getUnits(placement);
    final unit = units.isNotEmpty ? units.first : null;
    _reportEvent(
      AdEventType.showFail,
      placement,
      unit?.type,
      unit?.source,
      unit?.id,
      errorReason: errorReason,
      eventName: eventName,
    );
  }

  Future<void> preloadPlacements(
    Iterable<PlacementType> placements, {
    required String eventName,
  }) async {
    final c = await _configRepository.getConfig();
    final list = placements.toSet();

    for (final p in list) {
      final policy = c.getPolicy(p);
      final units = c.getUnits(p);
      if (units.any(
        (unit) =>
            unit.type.isFullscreen ||
            (policy.isFullscreen && unit.type == AdType.native),
      )) {
        unawaited(preload(p, eventName: eventName));
      }
      if (units.any(
        (unit) =>
            unit.type.isNative &&
            (!policy.isFullscreen || unit.type.isDoubleNative),
      )) {
        unawaited(preloadNative(p, eventName: eventName));
      }
    }
  }
}

class _AdPoolStore {
  final Map<PlacementType, PlacementAdPool> _pools = {};

  PlacementAdPool? operator [](PlacementType placement) => _pools[placement];

  bool hasAd(PlacementType placement) => _pools[placement]?.hasAd ?? false;

  List<PlacementAdSlot> slots(PlacementType placement) =>
      _pools[placement]?.slots ?? const [];

  bool hasCacheKey(PlacementType placement, String cacheKey) {
    return slots(placement).any((slot) => slot.cacheKey == cacheKey);
  }

  List<PlacementAdSlot> beginLoading(PlacementType placement) {
    final currentSlots = List<PlacementAdSlot>.of(slots(placement));
    _pools[placement] = PlacementAdPool(
      placement: placement,
      slots: currentSlots,
      isLoading: true,
    );
    return currentSlots;
  }

  void setSlots(
    PlacementType placement,
    List<PlacementAdSlot> slots, {
    Object? lastError,
  }) {
    if (slots.isEmpty && lastError == null) {
      _pools.remove(placement);
      return;
    }
    _pools[placement] = PlacementAdPool(
      placement: placement,
      slots: List.unmodifiable(slots),
      lastError: lastError,
    );
  }

  void add(PlacementType placement, PlacementAdSlot slot) {
    setSlots(placement, [...slots(placement), slot]);
  }

  void remove(PlacementType placement) {
    _pools.remove(placement);
  }

  void removeSlot(PlacementType placement, PlacementAdSlot slot) {
    final kept = slots(
      placement,
    ).where((item) => !identical(item.ad, slot.ad)).toList();
    setSlots(placement, kept);
  }
}

enum _AdLoadKind { fullscreen, native }

class _AdShowContext {
  _AdShowContext(this._context);

  final BuildContext? _context;

  BuildContext? get current {
    final context = _context;
    if (context == null || !context.mounted) {
      return null;
    }
    return context;
  }
}

class _PolicyOverrideConfigRepository implements AdConfigRepository {
  _PolicyOverrideConfigRepository(
    this._delegate,
    Map<PlacementType, PlacementPolicy> policies,
  ) : _policies = Map<PlacementType, PlacementPolicy>.unmodifiable(policies);

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
      samePlacementCdSeconds: config.samePlacementCdSeconds,
      differentPlacementCdSeconds: config.differentPlacementCdSeconds,
      commonPlacements: config.commonPlacements,
      highValuePlacement: config.highValuePlacement,
      placements: config.placements,
      policies: _policies,
    );
  }
}
