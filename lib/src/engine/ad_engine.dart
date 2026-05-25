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

    log.v('🏁 [engine] start');
    await _sdkInitializer.initAll();
    await _configRepository.getConfig();
    _initialized = true;
    log.v('🏁 [engine] ready');
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
        log.v(
          '📥 [preload] common: request=${placement.name} '
          'common=${common.name} event=$eventName',
        );
        loaded = await preload(common, eventName: eventName) || loaded;
      }
      return loaded;
    }

    if (_fullscreenLoadingFutures.containsKey(placement)) {
      log.v(
        '📥 [preload] wait: placement=${placement.name} '
        'event=$eventName',
      );
      return await _fullscreenLoadingFutures[placement]!;
    }

    final current = _fullscreenPools[placement];
    final targetCount = config.fullscreenCacheSizeFor(placement);
    if ((current?.count ?? 0) >= targetCount) {
      log.v(
        '📥 [preload] skip: placement=${placement.name} reason=has_cache '
        'cached=${current?.count ?? 0}/$targetCount event=$eventName',
      );
      return true;
    }

    log.v(
      '📥 [preload] start: placement=${placement.name} kind=fullscreen '
      'cached=${current?.count ?? 0}/$targetCount event=$eventName',
    );
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
  }) async {
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
      final targetCount = config.fullscreenCacheSizeFor(placement);
      final units =
          config
              .getUnits(placement)
              .where((unit) => unit.isValid)
              .where((unit) => policy.supports(unit.type))
              .where((unit) => unit.type.isFullscreen)
              .where(
                (unit) =>
                    !_hasCachedAd(placement, unit.cacheKey, native: false),
              )
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      if (units.isEmpty) {
        log.v(
          '📥 [preload] empty: placement=${placement.name} '
          'kind=fullscreen cached=${currentSlots.length}/$targetCount',
        );
        _fullscreenPools[placement] = PlacementAdPool(
          placement: placement,
          slots: currentSlots,
        );
        return false;
      }

      log.v(
        '📥 [preload] candidates: placement=${placement.name} '
        'kind=fullscreen units=${units.length} target=$targetCount',
      );

      Object? lastError;
      for (final unit in units) {
        log.v(
          '📥 [preload] try: placement=${placement.name} '
          'source=${unit.source.name} type=${unit.type.name} '
          'id=${unit.id} weight=${unit.weight} cacheKey=${unit.cacheKey} '
          'timeout=${config.loadTimeoutFor(unit).inSeconds}s '
          'cached=${currentSlots.length}/$targetCount event=$eventName',
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
          log.v(
            '✅ [preload] success: placement=${placement.name} '
            'source=${unit.source.name} type=${unit.type.name} id=${unit.id} '
            'cached=${currentSlots.length}/$targetCount',
          );
          if (currentSlots.length >= targetCount) {
            return true;
          }
          continue;
        }

        lastError = result.error;
        log.v(
          '❌ [preload] fail: placement=${placement.name} '
          'source=${unit.source.name} type=${unit.type.name} id=${unit.id} '
          'cached=${currentSlots.length}/$targetCount error=$lastError',
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

      log.v(
        '❌ [preload] exhausted: placement=${placement.name} '
        'kind=fullscreen cached=${currentSlots.length}/$targetCount '
        'lastError=$lastError',
      );
      _fullscreenPools[placement] = PlacementAdPool(
        placement: placement,
        slots: List.unmodifiable(currentSlots),
        lastError: lastError,
      );
      return currentSlots.isNotEmpty;
    } catch (e) {
      log.e('❌ [preload] fatal: placement=${placement.name} error=$e');
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
    final targetCount = type.isNative
        ? config.nativeCacheSizeFor(placement)
        : config.fullscreenCacheSizeFor(placement);
    final pools = type.isNative ? _nativePools : _fullscreenPools;
    final current = pools[placement];
    final hasSameAd =
        current?.slots.any((slot) => slot.cacheKey == cacheKey) == true;
    if (hasSameAd || (current?.count ?? 0) >= targetCount) {
      log.v(
        '📥 [late_load] discard: placement=${placement.name} '
        'source=${source.name} type=${type.name} id=$adUnitId '
        'cacheKey=$cacheKey cached=${current?.count ?? 0}/$targetCount '
        'reason=${hasSameAd ? 'duplicate' : 'pool_full'}',
      );
      _adapterRegistry.get(source, type).dispose(ad);
      return;
    }

    log.v(
      '📥 [late_load] accept: placement=${placement.name} '
      'source=${source.name} type=${type.name} id=$adUnitId '
      'cacheKey=$cacheKey cached=${current?.count ?? 0}/$targetCount',
    );
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
    required String eventName,
    VoidCallback? onAdShowed,
  }) async {
    final placementValue = placementLabel ?? placement.name;
    log.v(
      '🚀 [show] request: placement=${placement.name} '
      'label=$placementValue event=$eventName',
    );
    final adConfig = await config;
    final requestPlacement = placement;
    final showPlacement = _resolveShowPlacement(adConfig, requestPlacement);
    final isFallbackPlacement = showPlacement != requestPlacement;
    final policy = adConfig.getPolicy(showPlacement);
    final preferHighValue =
        !isFallbackPlacement && policy.preferHighValueOnShow;
    log.v(
      '🚀 [show] resolved: request=${requestPlacement.name} '
      'show=${showPlacement.name} commonResolved=$isFallbackPlacement '
      'waitForLoad=${policy.waitForLoadOnShow} '
      'preferHighValue=$preferHighValue',
    );

    final guardResult = await _guard.canShow(
      placement: showPlacement,
      configRepository: _configRepository,
    );
    if (!guardResult.allowed) {
      log.v(
        '🚫 [show] blocked: $placementValue reason=${guardResult.reason?.name}',
      );
      return false;
    }

    if (!(_fullscreenPools[showPlacement]?.hasAd ?? false)) {
      if (policy.waitForLoadOnShow) {
        log.v(
          '📥 [show] no_cache, try_preload: placement=${showPlacement.name} '
          'event=$eventName',
        );
        await preload(showPlacement, eventName: eventName);
      } else {
        log.v('📥 [show] no_cache, skip_wait: placement=${showPlacement.name}');
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
      if (policy.showNotReadyToast) {
        SmartDialog.showToast(
          policy.notReadyMsg ?? 'The ad is not ready, please try again later.',
        );
      }
      return false;
    }

    return _showSlot(
      slot: slot,
      reportPlacement: showPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
    );
  }

  Future<bool> showSequence(
    PlacementType placement, {
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
  }) async {
    final adConfig = await config;
    final showPlacement = _resolveShowPlacement(adConfig, placement);
    final policy = adConfig.getPolicy(showPlacement);

    if (!(_fullscreenPools[showPlacement]?.hasAd ?? false) &&
        policy.waitForLoadOnShow) {
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
      final refillFuture = _preloadMissingConfiguredSlot(
        showPlacement,
        firstSlot,
        eventName: eventName,
      );
      final firstShown = await _showSlot(
        slot: firstSlot,
        reportPlacement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        onAdShowed: onAdShowed,
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
        reportPlacement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        onAdShowed: onAdShowed,
      );
      return true;
    }

    final firstShown = await _showSlot(
      slot: firstSlot,
      reportPlacement: showPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
    );
    if (!firstShown) {
      return false;
    }
    return _showSlot(
      slot: secondSlot,
      reportPlacement: showPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
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
        log.v(
          '📥 [preload] common: request=native:${placement.name} '
          'common=native:${common.name} event=$eventName',
        );
        loaded = await preloadNative(common, eventName: eventName) || loaded;
      }
      return loaded;
    }

    if (_nativeLoadingFutures.containsKey(placement)) {
      log.v(
        '📥 [preload] wait: placement=${placement.name} kind=native '
        'event=$eventName',
      );
      return await _nativeLoadingFutures[placement]!;
    }

    final current = _nativePools[placement];
    final targetCount = config.nativeCacheSizeFor(placement);
    if ((current?.count ?? 0) >= targetCount) {
      log.v(
        '📥 [preload] skip: placement=${placement.name} kind=native '
        'reason=has_cache cached=${current?.count ?? 0}/$targetCount '
        'event=$eventName',
      );
      return true;
    }

    log.v(
      '📥 [preload] start: placement=${placement.name} kind=native '
      'cached=${current?.count ?? 0}/$targetCount event=$eventName',
    );
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
  }) async {
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
              .where((u) => u.type.isNative)
              .where((u) => !_hasCachedAd(placement, u.cacheKey, native: true))
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      log.v(
        '📥 [preload] candidates: placement=${placement.name} '
        'kind=native units=${units.length} target=$targetCount',
      );
      for (final unit in units) {
        log.v(
          '📥 [preload] try: placement=${placement.name} '
          'source=${unit.source.name} type=${unit.type.name} '
          'id=${unit.id} weight=${unit.weight} cacheKey=${unit.cacheKey} '
          'timeout=${config.loadTimeoutFor(unit).inSeconds}s '
          'cached=${currentSlots.length}/$targetCount event=$eventName',
        );
        _reportEvent(
          AdEventType.loadRequested,
          placement,
          unit.type,
          unit.source,
          unit.id,
          eventName: eventName,
        );
        final adapter = _adapterRegistry.get(unit.source, AdType.native);
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
            loadedType: AdType.native,
            adUnitId: unit.id,
            cacheKey: unit.cacheKey,
            loadedAt: DateTime.now(),
          );
          currentSlots.add(loadedSlot);
          _nativePools[placement] = PlacementAdPool(
            placement: placement,
            slots: List.unmodifiable(currentSlots),
          );
          _scheduleNativeRefresh(
            placement,
            unit.refreshMinutes,
            eventName: eventName,
          );
          _reportEvent(
            AdEventType.loadSucceeded,
            placement,
            unit.type,
            unit.source,
            unit.id,
            eventName: eventName,
          );
          if (currentSlots.length >= targetCount) {
            log.v(
              '✅ [preload] success: placement=${placement.name} '
              'kind=native cached=${currentSlots.length}/$targetCount',
            );
            return true;
          }
        }
      }
      _nativePools[placement] = PlacementAdPool(
        placement: placement,
        slots: List.unmodifiable(currentSlots),
      );
      if (currentSlots.isNotEmpty) {
        log.v(
          '✅ [preload] partial: placement=${placement.name} '
          'kind=native cached=${currentSlots.length}/$targetCount',
        );
      } else {
        log.v(
          '❌ [preload] exhausted: placement=${placement.name} '
          'kind=native cached=0/$targetCount',
        );
      }
      return currentSlots.isNotEmpty;
    } catch (e) {
      log.e(
        '❌ [preload] fatal: placement=${placement.name} kind=native error=$e',
      );
      _nativePools[placement] = PlacementAdPool(
        placement: placement,
        slots: currentSlots,
        lastError: e,
      );
      return currentSlots.isNotEmpty;
    }
  }

  Object? getNativeAd(
    PlacementType placement, {
    String? placementLabel,
    required String eventName,
  }) {
    final slot = _nativePools[placement]?.slots.firstOrNull;
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
    final slots =
        _nativePools[placement]?.slots.take(count).toList() ??
        const <PlacementAdSlot>[];
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
        _nativePools.remove(placement);
        preloadNative(placement, eventName: eventName);
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
      final configuredSlots =
          _fullscreenPools[showPlacement]?.slots ?? const [];
      final configuredFirst = configuredSlots.firstOrNull;
      final shouldUseHighValue =
          highValueSlot != null &&
          (configuredFirst?.loadedType?.isFullscreen ?? true);
      if (shouldUseHighValue) {
        log.v(
          '🚀 [show] select_high_value: request=${requestedPlacement.name} '
          'show=${showPlacement.name} highValue=${highValuePlacement.name} '
          'id=${highValueSlot.adUnitId} type=${highValueSlot.loadedType?.name}',
        );
        return highValueSlot;
      }
    }

    final slot = _firstUsableFullscreenSlot(
      showPlacement,
      excludedSlots: excludedSlots,
    );
    if (slot != null) {
      log.v(
        '🚀 [show] select_configured: placement=${showPlacement.name} '
        'id=${slot.adUnitId} type=${slot.loadedType?.name}',
      );
    }
    return slot;
  }

  PlacementAdSlot? _firstUsableFullscreenSlot(
    PlacementType placement, {
    Set<PlacementAdSlot> excludedSlots = const {},
  }) {
    final slots = _fullscreenPools[placement]?.slots ?? const [];
    for (final slot in slots) {
      if (!excludedSlots.contains(slot) &&
          slot.ad != null &&
          (slot.loadedType?.isFullscreen ?? false)) {
        return slot;
      }
    }
    return null;
  }

  Future<bool> _showSlot({
    required PlacementAdSlot slot,
    required PlacementType reportPlacement,
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
  }) async {
    final slotPlacement = slot.placement;
    final adConfig = await config;
    final slotPolicy = adConfig.getPolicy(slotPlacement);
    final adapter = _adapterRegistry.get(slot.loadedSource!, slot.loadedType!);

    log.v(
      '🚀 [show] start: reportPlacement=${reportPlacement.name} '
      'cachePlacement=${slotPlacement.name} source=${slot.loadedSource?.name} '
      'type=${slot.loadedType?.name} id=${slot.adUnitId} '
      'event=$eventName',
    );
    _guard.markShowStarted(slotPlacement, slotPolicy);
    final result = await adapter.show(
      placement: reportPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      ad: slot.ad!,
      reporter: _reporter,
      onAdShowed: onAdShowed,
      onClosed: () {
        _removeCachedAd(slotPlacement, slot, native: false);
        unawaited(preload(slotPlacement, eventName: eventName));
      },
    );
    if (result.shown) {
      log.v(
        '✅ [show] completed: reportPlacement=${reportPlacement.name} '
        'cachePlacement=${slotPlacement.name} id=${slot.adUnitId}',
      );
      _guard.markShowCompleted(slotPlacement, slotPolicy);
    } else {
      log.v(
        '❌ [show] failed: reportPlacement=${reportPlacement.name} '
        'cachePlacement=${slotPlacement.name} id=${slot.adUnitId} '
        'error=${result.error}',
      );
      _guard.markShowFailed(slotPlacement, slotPolicy);
      _removeCachedAd(slotPlacement, slot, native: false);
    }
    return result.shown;
  }

  Future<void> _preloadMissingConfiguredSlot(
    PlacementType placement,
    PlacementAdSlot existingSlot, {
    required String eventName,
  }) async {
    log.v(
      '📥 [show_sequence] refill missing pair: ${placement.name} '
      'existing=${existingSlot.adUnitId}',
    );
    await preload(placement, eventName: eventName);
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
    AdType t,
    AdSource s,
    String id, {
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

  Future<void> preloadPlacements(
    Iterable<PlacementType> placements, {
    required String eventName,
  }) async {
    final c = await _configRepository.getConfig();
    final list = placements.toSet();
    log.v(
      '📥 [preload_batch] start: placements=${list.map((p) => p.name).join(',')} '
      'event=$eventName',
    );

    for (final p in list) {
      final units = c.getUnits(p);
      if (units.any((unit) => unit.type.isFullscreen)) {
        unawaited(preload(p, eventName: eventName));
      }
      if (units.any((unit) => unit.type.isNative)) {
        unawaited(preloadNative(p, eventName: eventName));
      }
    }
  }
}
