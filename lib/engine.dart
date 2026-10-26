import 'dart:async';

import 'package:flutter/widgets.dart';

import 'models.dart';
import 'platform.dart';

/// Generic ad cache service managing ad slots per placement.
///
/// Replaces the old three `_AdPoolStore` instances with a single service.
/// Handles slot CRUD, deduplication by cache key, loading state, and
/// attribution tracking (replacing adapter-level static maps).
///
/// ---
/// 泛型广告缓存服务，每个 placement 管理广告槽位。
/// 替代旧的三个 `_AdPoolStore`，统一处理槽位增删查、
/// cacheKey 去重、加载状态和 attribution 管理。
class AdCacheService {
  final Map<_AdCacheScope, List<AdSlotState>> _cache = {};

  _AdCacheScope _scope(PlacementType placement, String? cacheId) =>
      _AdCacheScope(placement, cacheId);

  /// Attribution map keyed by ad object identity.
  /// Replaces the static maps in adapters.
  final Map<Object, AdAttribution> _attributions = {};

  /// Whether [placement] has at least one loaded ad slot.
  bool hasSlot(PlacementType placement, {String? cacheId}) {
    final slots = _cache[_scope(placement, cacheId)];
    return slots != null && slots.any((s) => s is AdSlotLoaded);
  }

  /// Returns all ad slots for [placement], filtered to loaded only.
  List<AdSlotLoaded> getSlots(PlacementType placement, {String? cacheId}) {
    final slots = _cache[_scope(placement, cacheId)];
    if (slots == null) {
      return const [];
    }
    return slots.whereType<AdSlotLoaded>().toList();
  }

  /// Returns the count of loaded slots for [placement].
  int countFor(PlacementType placement, {String? cacheId}) =>
      getSlots(placement, cacheId: cacheId).length;

  /// Checks if a slot with [cacheKey] already exists.
  bool hasSlotWithKey(
    PlacementType placement,
    String cacheKey, {
    String? cacheId,
  }) {
    return getSlots(
      placement,
      cacheId: cacheId,
    ).any((s) => s.cacheKey == cacheKey);
  }

  /// Returns the latest load error preserved for [placement], if any.
  Object? lastErrorFor(PlacementType placement, {String? cacheId}) {
    final slots = _cache[_scope(placement, cacheId)];
    if (slots == null) {
      return null;
    }

    for (final state in slots.reversed) {
      if (state is AdSlotFailed) {
        return state.error;
      }
    }
    return null;
  }

  /// Marks a placement as loading, preserving existing loaded slots.
  void beginLoading(PlacementType placement, {String? cacheId}) {
    final scope = _scope(placement, cacheId);
    final existing = getSlots(placement, cacheId: cacheId);
    if (existing.isEmpty) {
      _cache.remove(scope);
      return;
    }
    _cache[scope] = List<AdSlotState>.from(existing);
  }

  /// Commits the loaded slots for a placement (replaces existing).
  void commitSlots(
    PlacementType placement,
    List<AdSlotLoaded> slots, {
    Object? lastError,
    String? cacheId,
  }) {
    final scope = _scope(placement, cacheId);
    if (slots.isEmpty && lastError == null) {
      _cache.remove(scope);
      return;
    }
    final states = <AdSlotState>[...slots];
    if (lastError != null) {
      states.add(AdSlotFailed(placement: placement, error: lastError));
    }
    _cache[scope] = states;
  }

  /// Adds a single loaded slot to the cache.
  void addSlot(PlacementType placement, AdSlotLoaded slot, {String? cacheId}) {
    final existing = getSlots(placement, cacheId: cacheId);
    commitSlots(placement, [...existing, slot], cacheId: cacheId);
  }

  /// Removes a specific loaded slot.
  void removeSlot(
    PlacementType placement,
    AdSlotLoaded slot, {
    String? cacheId,
  }) {
    final kept = getSlots(
      placement,
      cacheId: cacheId,
    ).where((s) => s.ad != slot.ad).toList();
    _attributions.remove(slot.ad);
    commitSlots(placement, kept, cacheId: cacheId);
  }

  /// Clears all slots for a placement.
  void clear(PlacementType placement, {String? cacheId}) {
    final slots = getSlots(placement, cacheId: cacheId);
    for (final s in slots) {
      _attributions.remove(s.ad);
    }
    _cache.remove(_scope(placement, cacheId));
  }

  /// Returns the first loaded slot, or null.
  AdSlotLoaded? firstSlot(PlacementType placement, {String? cacheId}) {
    return getSlots(placement, cacheId: cacheId).firstOrNull;
  }

  /// Returns the first loaded slot excluding those in [exclude].
  AdSlotLoaded? firstSlotExcluding(
    PlacementType placement,
    Set<AdSlotLoaded> exclude, {
    String? cacheId,
  }) {
    for (final slot in getSlots(placement, cacheId: cacheId)) {
      if (!exclude.contains(slot)) {
        return slot;
      }
    }
    return null;
  }

  // --- Attribution management ---

  /// Sets the attribution for an ad object.
  void setAttribution(
    Object ad,
    PlacementType placement, {
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    final existing = _attributions[ad];
    if (existing == null) {
      _attributions[ad] = AdAttribution(
        placement: placement,
        eventName: eventName,
        extras: extras,
      );
      return;
    }
    existing
      ..placement = placement
      ..eventName = eventName
      ..extras = extras;
  }

  /// Gets the attribution for an ad object.
  AdAttribution? getAttribution(Object ad) {
    return _attributions[ad];
  }

  /// Removes attribution for a disposed ad.
  void removeAttribution(Object ad) {
    _attributions.remove(ad);
  }

  /// Clears all data (used during [AdPlugin.dispose]).
  void disposeAll() {
    _cache.clear();
    _attributions.clear();
  }

  /// Removes and returns every loaded slot so the owner can dispose SDK ads.
  List<AdSlotLoaded> drainAll() {
    final slots = _cache.values
        .expand((states) => states.whereType<AdSlotLoaded>())
        .toList(growable: false);
    disposeAll();
    return slots;
  }
}

class _AdCacheScope {
  const _AdCacheScope(this.placement, this.cacheId);

  final PlacementType placement;
  final String? cacheId;

  @override
  bool operator ==(Object other) =>
      other is _AdCacheScope &&
      other.placement == placement &&
      other.cacheId == cacheId;

  @override
  int get hashCode => Object.hash(placement, cacheId);
}

/// Converts raw [AdRawCallback] instances emitted by adapters into
/// structured [AdEvent] objects for reporting.
class AdEventMapper {
  AdEvent map(
    AdRawCallback callback, {
    PlacementType? placement,
    required String eventName,
    Map<String, dynamic>? extras,
    AdType? adType,
    AdSource? source,
    String? adUnitId,
  }) {
    switch (callback) {
      case AdImpressionCallback(:final network):
        return AdEvent(
          eventType: AdEventType.showSuccess,
          placement: placement,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          extras: extras,
          network: network,
        );

      case AdPaidCallback(
        :final valueMicros,
        :final currencyCode,
        :final network,
      ):
        return AdEvent(
          eventType: AdEventType.income,
          placement: placement,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          revenue: valueMicros,
          currency: currencyCode,
          timestamp: DateTime.now(),
          eventName: eventName,
          extras: extras,
          network: network,
        );

      case AdClickedCallback(:final network):
        return AdEvent(
          eventType: AdEventType.clicked,
          placement: placement,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          extras: extras,
          network: network,
        );

      case AdClosedCallback(:final network):
        return AdEvent(
          eventType: AdEventType.close,
          placement: placement,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          extras: extras,
          network: network,
        );

      case AdRewardedCallback(:final amount, :final label, :final network):
        return AdEvent(
          eventType: AdEventType.reward,
          placement: placement,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          rewardAmount: amount,
          rewardLabel: label,
          timestamp: DateTime.now(),
          eventName: eventName,
          extras: extras,
          network: network,
        );

      case AdShowedCallback(:final network):
        return AdEvent(
          eventType: AdEventType.showSuccess,
          placement: placement,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
          eventName: eventName,
          extras: extras,
          network: network,
        );

      case AdShowFailedCallback(
        :final errorCode,
        :final errorMessage,
        :final network,
      ):
        return AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          errorCode: errorCode,
          errorReason: errorMessage,
          timestamp: DateTime.now(),
          eventName: eventName,
          extras: extras,
          network: network,
        );
    }
  }
}

/// 广告展示被拦截的原因。
enum AdGuardBlockReason {
  /// 当前已有全屏广告正在展示（互斥）
  fullscreenShowing,

  /// 同一广告位的 CD 冷却未结束
  samePlacementCooldown,

  /// 跨广告位的全局 CD 冷却未结束
  differentPlacementCooldown,
}

class AdGuardResult {
  const AdGuardResult.allowed()
    : allowed = true,
      reason = null,
      retryAfterSeconds = null,
      relatedPlacement = null;

  const AdGuardResult.blocked({
    required this.reason,
    this.retryAfterSeconds,
    this.relatedPlacement,
  }) : allowed = false;

  final bool allowed;
  final AdGuardBlockReason? reason;
  final int? retryAfterSeconds;
  final PlacementType? relatedPlacement;
}

/// 广告展示策略守卫。
///
/// 负责 CD 冷却（Same CD / Global CD）和全屏互斥检查。
/// 全屏判断由 [PlacementPolicy] 驱动，所有全屏广告统一执行 CD。
///
/// ## 冷却逻辑
/// - 同广告位冷却：同一个 placement 在 `ad_cd` 秒内重复触发会被拦截
/// - 跨广告位冷却：刚展示过其他全屏 placement 后，`ad_cd` 秒内展示当前 placement 会被拦截
/// - 全屏互斥：同一时间只允许一个全屏广告展示
class AdDisplayGuard {
  final Map<PlacementType, DateTime> _lastShownByPlacement = {};
  DateTime? _lastGlobalShownAt;
  PlacementType? _lastGlobalPlacement;
  bool _isFullscreenShowing = false;

  void resetForTesting() {
    _lastShownByPlacement.clear();
    _lastGlobalShownAt = null;
    _lastGlobalPlacement = null;
    _isFullscreenShowing = false;
  }

  /// 检查是否可以展示指定广告位的广告。
  Future<AdGuardResult> canShow({
    required PlacementType placement,
    required AdConfigRepository configRepository,
  }) async {
    final config = await configRepository.getConfig();
    final policy = config.getPolicy(placement);
    if (!policy.isFullscreen) {
      return const AdGuardResult.allowed();
    }

    if (_isFullscreenShowing) {
      return const AdGuardResult.blocked(
        reason: AdGuardBlockReason.fullscreenShowing,
      );
    }

    final now = DateTime.now();
    final last = _lastShownByPlacement[placement];
    if (last != null) {
      final elapsed = now.difference(last).inSeconds;
      if (elapsed < config.adCdSeconds) {
        return AdGuardResult.blocked(
          reason: AdGuardBlockReason.samePlacementCooldown,
          retryAfterSeconds: config.adCdSeconds - elapsed,
          relatedPlacement: placement,
        );
      }
    }

    final lastGlobalShownAt = _lastGlobalShownAt;
    final lastGlobalPlacement = _lastGlobalPlacement;
    if (lastGlobalShownAt != null &&
        lastGlobalPlacement != null &&
        lastGlobalPlacement != placement &&
        now.difference(lastGlobalShownAt).inSeconds < config.adCdSeconds) {
      final elapsed = now.difference(lastGlobalShownAt).inSeconds;
      return AdGuardResult.blocked(
        reason: AdGuardBlockReason.differentPlacementCooldown,
        retryAfterSeconds: config.adCdSeconds - elapsed,
        relatedPlacement: lastGlobalPlacement,
      );
    }

    return const AdGuardResult.allowed();
  }

  /// 广告开始展示时调用，标记全屏互斥状态。
  void markShowStarted(PlacementType placement, PlacementPolicy policy) {
    if (policy.isFullscreen) {
      _isFullscreenShowing = true;
    }
  }

  /// 广告正常关闭时调用，记录 CD 时间并清除互斥标记。
  void markShowCompleted(PlacementType placement) {
    final now = DateTime.now();
    _lastShownByPlacement[placement] = now;

    _lastGlobalShownAt = now;
    _lastGlobalPlacement = placement;
    _isFullscreenShowing = false;
  }

  /// 广告展示失败时调用，仅清除互斥标记，不记录 CD 时间。
  void markShowFailed(PlacementType placement, PlacementPolicy policy) {
    if (policy.isFullscreen) {
      _isFullscreenShowing = false;
    }
  }
}

/// Manages ad loading: preloading, waterfall loading, late-ad handling,
/// and adapter-callback-to-event conversion.
///
/// Replaces the loading portions of the old [AdEngine].
class AdLoaderService {
  final AdConfigRepository _configRepo;
  final AdAdapterRegistry _adapterRegistry;
  final AdCacheService _cache;
  final AdEventMapper _eventMapper;
  final AdEventReporter _reporter;
  final AppLogger _logger;

  AdLoaderService({
    required AdConfigRepository configRepository,
    required AdAdapterRegistry adapterRegistry,
    required AdCacheService cache,
    required AdEventMapper eventMapper,
    required AdEventReporter reporter,
    AppLogger? logger,
  }) : _configRepo = configRepository,
       _adapterRegistry = adapterRegistry,
       _cache = cache,
       _eventMapper = eventMapper,
       _reporter = reporter,
       _logger = logger ?? log;

  // --- Loading future dedup ---
  final Map<PlacementType, Future<bool>> _fullscreenLoadingFutures = {};
  final Map<_NativeLoadScope, Future<bool>> _nativeLoadingFutures = {};
  final Map<PlacementType, Future<bool>> _bannerLoadingFutures = {};

  final CancellationToken _cancellationToken = CancellationToken();
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancellationToken.cancel();
    _fullscreenLoadingFutures.clear();
    _nativeLoadingFutures.clear();
    _bannerLoadingFutures.clear();
  }

  // --- Public API ---

  Future<bool> preload(
    PlacementType placement, {
    required String eventName,
  }) async {
    if (_disposed) return false;
    final config = await _configRepo.getConfig();
    final inventoryPlacement = _fullscreenInventoryPlacement(config, placement);
    final targets = <PlacementType>[
      ?config.highValuePlacement,
      inventoryPlacement,
    ].where(config.hasPlacement).toSet();
    if (targets.isEmpty) return false;

    final results = await Future.wait(
      targets.map((target) => preloadPlacement(target, eventName: eventName)),
    );
    return results.any((loaded) => loaded);
  }

  PlacementType _fullscreenInventoryPlacement(
    AdConfig config,
    PlacementType requested,
  ) {
    if (requested.name == 'open' ||
        config.commonPlacements.contains(requested)) {
      return requested;
    }
    return config.commonPlacements.where(config.hasPlacement).firstOrNull ??
        requested;
  }

  Future<bool> preloadPlacement(
    PlacementType placement, {
    required String eventName,
  }) async {
    if (_disposed) return false;
    final config = await _configRepo.getConfig();
    if (!config.hasPlacement(placement)) return false;

    if (_fullscreenLoadingFutures.containsKey(placement)) {
      return _fullscreenLoadingFutures[placement]!;
    }

    final targetCount = config.fullscreenCacheSizeFor(placement);
    if (_cache.countFor(placement) >= targetCount) return true;

    final future = _loadFullscreen(placement, eventName: eventName);
    _fullscreenLoadingFutures[placement] = future;
    try {
      return await future;
    } finally {
      _fullscreenLoadingFutures.remove(placement);
    }
  }

  Future<bool> preloadNative(
    PlacementType placement, {
    required String eventName,
    String? cacheId,
  }) async {
    if (_disposed) return false;
    final config = await _configRepo.getConfig();
    if (!config.hasPlacement(placement)) {
      var loaded = false;
      for (final common in _configuredCommonPlacements(config, placement)) {
        loaded =
            await preloadNative(
              common,
              eventName: eventName,
              cacheId: cacheId,
            ) ||
            loaded;
      }
      return loaded;
    }

    final scope = _NativeLoadScope(placement, cacheId);
    if (_nativeLoadingFutures.containsKey(scope)) {
      return _nativeLoadingFutures[scope]!;
    }

    final targetCount = config.nativeCacheSizeFor(placement);
    if (_cache.countFor(placement, cacheId: cacheId) >= targetCount) {
      return true;
    }

    final future = _loadNative(
      placement,
      eventName: eventName,
      cacheId: cacheId,
    );
    _nativeLoadingFutures[scope] = future;
    try {
      return await future;
    } finally {
      _nativeLoadingFutures.remove(scope);
    }
  }

  Future<bool> preloadBanner(
    PlacementType placement, {
    required String eventName,
  }) async {
    if (_disposed) return false;
    final config = await _configRepo.getConfig();
    if (!config.hasPlacement(placement)) return false;

    if (_bannerLoadingFutures.containsKey(placement)) {
      return _bannerLoadingFutures[placement]!;
    }

    final targetCount = config.cacheSizeFor(placement);
    if (_cache.countFor(placement) >= targetCount) return true;

    final future = _loadBanner(placement, eventName: eventName);
    _bannerLoadingFutures[placement] = future;
    try {
      return await future;
    } finally {
      _bannerLoadingFutures.remove(placement);
    }
  }

  Future<void> preloadPlacements(
    Iterable<PlacementType> placements, {
    required String eventName,
  }) async {
    if (_disposed) return;
    final config = await _configRepo.getConfig();
    final list = placements.toSet();
    final loads = <Future<bool>>[];

    for (final p in list) {
      final policy = config.getPolicy(p);
      final units = config.getUnits(p);

      if (units.any(
        (u) =>
            u.type.isFullscreen ||
            (policy.isFullscreen && u.type == AdType.native),
      )) {
        loads.add(preload(p, eventName: eventName));
      }
      if (units.any(
        (u) =>
            u.type.isNative && (!policy.isFullscreen || u.type.isDoubleNative),
      )) {
        loads.add(preloadNative(p, eventName: eventName));
      }
      if (units.any((u) => u.type.isBanner)) {
        loads.add(preloadBanner(p, eventName: eventName));
      }
    }
    await Future.wait(loads);
  }

  // --- Internal load methods ---

  Future<bool> _loadFullscreen(
    PlacementType placement, {
    required String eventName,
  }) async {
    return _waterfallLoad(
      placement: placement,
      eventName: eventName,
      isFullscreen: true,
      targetCountFor: (c) => c.fullscreenCacheSizeFor(placement),
      unitFilter: (config) {
        final policy = config.getPolicy(placement);
        return config
            .getUnits(placement)
            .where((u) => u.isValid)
            .where((u) => policy.supports(u.type))
            .where(
              (u) =>
                  u.type.isFullscreen ||
                  (policy.isFullscreen && u.type == AdType.native),
            )
            .where((u) => !_cache.hasSlotWithKey(placement, u.cacheKey));
      },
      adapterTypeFor: (u) => u.type.isNative ? AdType.native : u.type,
    );
  }

  Future<bool> _loadNative(
    PlacementType placement, {
    required String eventName,
    String? cacheId,
  }) async {
    return _waterfallLoad(
      placement: placement,
      eventName: eventName,
      isFullscreen: false,
      targetCountFor: (c) => c.cacheSizeFor(placement),
      unitFilter: (config) {
        final policy = config.getPolicy(placement);
        return config
            .getUnits(placement)
            .where((u) => u.isValid && policy.supports(u.type))
            .where((u) => !policy.isFullscreen || u.type.isDoubleNative)
            .where((u) => u.type.isNative)
            .where(
              (u) => !_cache.hasSlotWithKey(
                placement,
                u.cacheKey,
                cacheId: cacheId,
              ),
            );
      },
      adapterTypeFor: (_) => AdType.native,
      cacheId: cacheId,
      requireCompleteDoubleNative: true,
    );
  }

  Future<bool> _loadBanner(
    PlacementType placement, {
    required String eventName,
  }) async {
    return _waterfallLoad(
      placement: placement,
      eventName: eventName,
      isFullscreen: false,
      targetCountFor: (c) => c.cacheSizeFor(placement),
      unitFilter: (config) {
        final policy = config.getPolicy(placement);
        return config
            .getUnits(placement)
            .where((u) => u.isValid)
            .where((u) => policy.supports(u.type))
            .where((u) => u.type.isBanner)
            .where((u) => !_cache.hasSlotWithKey(placement, u.cacheKey));
      },
      adapterTypeFor: (_) => AdType.banner,
    );
  }

  /// Shared waterfall loading logic. Iterates through filtered ad units
  /// sorted by weight descending, loading each until the target count is
  /// reached or all units are exhausted.
  Future<bool> _waterfallLoad({
    required PlacementType placement,
    required String eventName,
    required bool isFullscreen,
    required int Function(AdConfig) targetCountFor,
    required Iterable<AdUnitConfig> Function(AdConfig) unitFilter,
    required AdType Function(AdUnitConfig) adapterTypeFor,
    void Function(AdUnitConfig)? onUnitLoaded,
    String? cacheId,
    bool requireCompleteDoubleNative = false,
  }) async {
    final config = await _configRepo.getConfig();
    final targetCount = targetCountFor(config);
    final units = unitFilter(config).toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));

    if (units.isEmpty) {
      _logger.v(
        '📥 [preload] exhausted: placement=${placement.name} '
        'reason=no_units event=$eventName',
      );
      return false;
    }

    _cache.beginLoading(placement, cacheId: cacheId);
    final existingSlots = _cache.getSlots(placement, cacheId: cacheId);
    final loadedSlots = <AdSlotLoaded>[];
    Object? lastError;

    final ct = _cancellationToken;

    for (final unit in units) {
      if (ct.isCancelled) break;

      _reportEvent(
        AdEventType.loadRequested,
        placement,
        unit.type,
        unit.source,
        unit.id,
        eventName: eventName,
      );

      final adapterType = adapterTypeFor(unit);
      final adapter = _adapterRegistry.tryGet(unit.source, adapterType);
      if (adapter == null) {
        lastError = StateError(
          'No adapter registered for source=${unit.source.name}, '
          'type=${adapterType.name}',
        );
        _reportEvent(
          AdEventType.loadFailed,
          placement,
          unit.type,
          unit.source,
          unit.id,
          errorReason: lastError.toString(),
          eventName: eventName,
        );
        continue;
      }

      Future<AdLoadResult<Object>> prepareAd() {
        if (adapter is InlineAdAdapter) {
          return adapter.prepare(
            placement: placement,
            unit: unit,
            timeout: config.loadTimeoutFor(unit),
            eventName: eventName,
            renderAsFullscreen: isFullscreen && unit.type.isNative,
            cancellationToken: ct,
            onCallback: _wrapCallback(placement, unit, eventName),
            onLateAdLoaded: (ad, type, adUnitId) {
              _handleLateAd(
                placement,
                ad,
                type,
                adUnitId,
                unit.cacheKey,
                unit.source,
                targetCount,
                cacheId,
              );
            },
          );
        }
        if (adapter is FullscreenAdAdapter) {
          return adapter.load(
            placement: placement,
            unit: unit,
            timeout: config.loadTimeoutFor(unit),
            eventName: eventName,
            renderAsFullscreen: isFullscreen && unit.type.isNative,
            cancellationToken: ct,
            onCallback: _wrapCallback(placement, unit, eventName),
            onLateAdLoaded: (ad, type, adUnitId) {
              _handleLateAd(
                placement,
                ad,
                type,
                adUnitId,
                unit.cacheKey,
                unit.source,
                targetCount,
                cacheId,
              );
            },
          );
        }
        return Future<AdLoadResult<Object>>.value(
          AdLoadResult.failure(
            type: adapterType,
            adUnitId: unit.id,
            error: StateError(
              'Adapter source=${unit.source.name}, type=${adapterType.name} '
              'does not implement a supported lifecycle',
            ),
          ),
        );
      }

      final result = await prepareAd();

      if (_disposed || ct.isCancelled) {
        if (result.isSuccess) {
          _adapterRegistry.dispose(unit.source, adapterType, result.ad!);
        }
        break;
      }

      if (result.isSuccess) {
        final slot = AdSlotLoaded(
          placement: placement,
          ad: result.ad!,
          source: unit.source,
          type: adapterType,
          adUnitId: unit.id,
          cacheKey: unit.cacheKey,
          loadedAt: DateTime.now(),
        );
        loadedSlots.add(slot);
        _cache.addSlot(placement, slot, cacheId: cacheId);
        _cache.setAttribution(slot.ad, placement, eventName: eventName);
        onUnitLoaded?.call(unit);

        _reportEvent(
          AdEventType.loadSucceeded,
          placement,
          unit.type,
          unit.source,
          unit.id,
          eventName: eventName,
        );

        if (existingSlots.length + loadedSlots.length >= targetCount) {
          _cache.commitSlots(placement, [
            ...existingSlots,
            ...loadedSlots,
          ], cacheId: cacheId);
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

    final requiredDoubleNativeCount = units
        .where((unit) => unit.type.isDoubleNative)
        .fold<int>(
          0,
          (count, unit) => unit.poolSize > count ? unit.poolSize : count,
        );
    if (requireCompleteDoubleNative &&
        requiredDoubleNativeCount > 0 &&
        existingSlots.length + loadedSlots.length < requiredDoubleNativeCount) {
      for (final slot in loadedSlots) {
        _adapterRegistry.dispose(slot.source, slot.type, slot.ad);
        _cache.removeAttribution(slot.ad);
      }
      _cache.commitSlots(
        placement,
        existingSlots,
        lastError: lastError ?? 'double_native_incomplete',
        cacheId: cacheId,
      );
      return false;
    }

    _cache.commitSlots(
      placement,
      [...existingSlots, ...loadedSlots],
      lastError: lastError,
      cacheId: cacheId,
    );

    if (loadedSlots.isEmpty) {
      _logger.v(
        '❌ [preload] exhausted: placement=${placement.name} '
        'event=$eventName lastError=$lastError',
      );
    }
    return loadedSlots.isNotEmpty;
  }

  void _handleLateAd(
    PlacementType placement,
    Object ad,
    AdType type,
    String adUnitId,
    String cacheKey,
    AdSource source,
    int targetCount,
    String? cacheId,
  ) {
    if (_disposed || _cancellationToken.isCancelled) {
      _adapterRegistry.dispose(source, type, ad);
      return;
    }
    if (_cache.hasSlotWithKey(placement, cacheKey, cacheId: cacheId) ||
        _cache.countFor(placement, cacheId: cacheId) >= targetCount) {
      _adapterRegistry.dispose(source, type, ad);
      return;
    }

    final slot = AdSlotLoaded(
      placement: placement,
      ad: ad,
      source: source,
      type: type,
      adUnitId: adUnitId,
      cacheKey: cacheKey,
      loadedAt: DateTime.now(),
    );
    _cache.addSlot(placement, slot, cacheId: cacheId);
  }

  // --- Callback wrapping ---

  /// Wraps an adapter's onCallback to look up attribution from cache,
  /// convert to AdEvent via AdEventMapper, and report.
  void Function(AdRawCallback) _wrapCallback(
    PlacementType placement,
    AdUnitConfig unit,
    String eventName,
  ) {
    return (callback) {
      // Look up attribution from cache by ad object
      final attr = _cache.getAttribution(callback.ad);
      final p = attr?.placement ?? placement;
      final en = attr?.eventName ?? eventName;
      final ex = attr?.extras;

      final event = _eventMapper.map(
        callback,
        placement: p,
        eventName: en,
        extras: ex,
        adType: unit.type,
        source: unit.source,
        adUnitId: unit.id,
      );
      _reporter.report(event);
      _logger.event(event);
    };
  }

  // --- Helpers ---

  Iterable<PlacementType> _configuredCommonPlacements(
    AdConfig config,
    PlacementType requested,
  ) {
    return config.commonPlacements.where(
      (placement) => placement != requested && config.hasPlacement(placement),
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
    _logger.event(event);
    _reporter.report(event);
  }
}

class _NativeLoadScope {
  const _NativeLoadScope(this.placement, this.cacheId);

  final PlacementType placement;
  final String? cacheId;

  @override
  bool operator ==(Object other) =>
      other is _NativeLoadScope &&
      other.placement == placement &&
      other.cacheId == cacheId;

  @override
  int get hashCode => Object.hash(placement, cacheId);
}

/// Manages ad display: show, showSequence, slot selection, placement
/// resolution, guard integration, and cached ad retrieval.
///
/// Replaces the display portions of the old [AdEngine].
class AdPresenter {
  final AdConfigRepository _configRepo;
  final AdAdapterRegistry _adapterRegistry;
  final AdCacheService _cache;
  final AdDisplayGuard _guard;
  final AdEventMapper _eventMapper;
  final AdEventReporter _reporter;
  final AdLoaderService _loader;
  final AppLogger _logger;

  AdPresenter({
    required AdConfigRepository configRepository,
    required AdAdapterRegistry adapterRegistry,
    required AdCacheService cache,
    required AdDisplayGuard guard,
    required AdEventMapper eventMapper,
    required AdEventReporter reporter,
    required AdLoaderService loader,
    AppLogger? logger,
  }) : _configRepo = configRepository,
       _adapterRegistry = adapterRegistry,
       _cache = cache,
       _guard = guard,
       _eventMapper = eventMapper,
       _reporter = reporter,
       _loader = loader,
       _logger = logger ?? log;

  // --- Fullscreen Show ---

  Future<AdShowResult> show(
    PlacementType placement, {
    BuildContext? context,
    required String eventName,
    Map<String, dynamic>? extras,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
    AdNotReadyCallback? onAdNotReady,
  }) async {
    final adConfig = await _configRepo.getConfig();
    final poolPlacements = _fullscreenPoolPlacements(adConfig, placement);
    final guardPlacement = poolPlacements.first;
    final guardPolicy = adConfig.getPolicy(guardPlacement);

    _logger.v(
      '🚀 [show] request=${placement.name} '
      'event=$eventName '
      'pool=${poolPlacements.map((p) => p.name).join(',')}',
    );

    // Guard check
    final guardResult = await _guard.canShow(
      placement: guardPlacement,
      configRepository: _configRepo,
    );
    if (!guardResult.allowed) {
      _logger.v(
        '🚫 [show] blocked: event=$eventName '
        'reason=${guardResult.reason?.name}',
      );
      _reportShowFail(
        placement: placement,
        eventName: eventName,
        extras: extras,
        errorReason: _guardErrorReason(guardResult),
      );
      return AdShowResult.failure(
        requestedPlacement: placement,
        errorReason: _guardErrorReason(guardResult),
      );
    }

    final slot = _firstPoolSlot(poolPlacements);

    if (slot == null) {
      final lastError = _firstPoolError(poolPlacements);
      _logger.v(
        '❌ [show] failed: reason=no_cache '
        'request=${placement.name} '
        'lastError=$lastError',
      );
      _reportShowFail(
        placement: placement,
        eventName: eventName,
        extras: extras,
        errorReason: 'no_cache',
      );
      unawaited(_loader.preload(placement, eventName: eventName));
      if (guardPolicy.showNotReadyToast && onAdNotReady != null) {
        onAdNotReady(
          AdNotReadyEvent(
            requestedPlacement: placement.name,
            showPlacement: guardPlacement.name,
            eventName: eventName,
            message: _notReadyMessage(guardPolicy, lastError),
          ),
        );
      }
      return AdShowResult.failure(
        error: lastError,
        requestedPlacement: placement,
        errorReason: 'no_cache',
      );
    }

    return _showSlot(
      slot: slot,
      showPlacement: placement,
      policy: adConfig.getPolicy(slot.placement),
      // ignore: use_build_context_synchronously
      context: context,
      eventName: eventName,
      extras: extras,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
  }

  List<PlacementType> _fullscreenPoolPlacements(
    AdConfig config,
    PlacementType requested,
  ) {
    final commonInventory = config.commonPlacements
        .where(config.hasPlacement)
        .firstOrNull;
    final inventoryPlacement = requested.name == 'open'
        ? requested
        : commonInventory ?? requested;
    final placements = <PlacementType>[
      ?config.highValuePlacement,
      inventoryPlacement,
    ].where(config.hasPlacement).toSet().toList();
    return placements.isEmpty ? [requested] : placements;
  }

  AdSlotLoaded? _firstPoolSlot(Iterable<PlacementType> placements) {
    for (final placement in placements) {
      final slot = _cache.firstSlot(placement);
      if (slot != null) return slot;
    }
    return null;
  }

  Object? _firstPoolError(Iterable<PlacementType> placements) {
    for (final placement in placements) {
      final error = _cache.lastErrorFor(placement);
      if (error != null) return error;
    }
    return null;
  }

  String _guardErrorReason(AdGuardResult result) {
    return switch (result.reason) {
      AdGuardBlockReason.samePlacementCooldown ||
      AdGuardBlockReason.differentPlacementCooldown => 'in_cd',
      _ => 'guard_blocked: ${result.reason?.name ?? 'unknown'}',
    };
  }

  /// Coordinates two common fullscreen placements and shows each at most once.
  Future<AdSequenceShowResult> showSequence(
    PlacementType placement, {
    BuildContext? context,
    required String eventName,
    Map<String, dynamic>? extras,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
    AdNotReadyCallback? onAdNotReady,
  }) async {
    final adConfig = await _configRepo.getConfig();
    final sequencePlacements = adConfig.commonPlacements
        .where(adConfig.hasPlacement)
        .take(2)
        .toList();
    if (sequencePlacements.length < 2) {
      final result = await show(
        placement,
        // ignore: use_build_context_synchronously
        context: context,
        eventName: eventName,
        extras: extras,
        onAdShowed: onAdShowed,
        closePassThroughPercent: closePassThroughPercent,
        onAdNotReady: onAdNotReady,
      );
      return AdSequenceShowResult(
        requestedPlacement: placement,
        results: [result],
        errorReason: result.errorReason,
      );
    }

    final guardPlacement = sequencePlacements.first;
    final guardPolicy = adConfig.getPolicy(guardPlacement);
    final guardResult = await _guard.canShow(
      placement: guardPlacement,
      configRepository: _configRepo,
    );
    if (!guardResult.allowed) {
      _reportShowFail(
        placement: placement,
        eventName: eventName,
        extras: extras,
        errorReason: _guardErrorReason(guardResult),
      );
      return AdSequenceShowResult(
        requestedPlacement: placement,
        errorReason: _guardErrorReason(guardResult),
      );
    }

    final initiallyAvailable = sequencePlacements
        .where(_cache.hasSlot)
        .toList();
    final highValue = adConfig.highValuePlacement;
    final highValueSlot = highValue == null
        ? null
        : _cache.firstSlot(highValue);
    if (initiallyAvailable.isEmpty && highValueSlot == null) {
      final lastError = _firstPoolError(sequencePlacements);
      _reportShowFail(
        placement: placement,
        eventName: eventName,
        extras: extras,
        errorReason: 'no_cache',
      );
      for (final target in sequencePlacements) {
        unawaited(_loader.preloadPlacement(target, eventName: eventName));
      }
      if (guardPolicy.showNotReadyToast && onAdNotReady != null) {
        onAdNotReady(
          AdNotReadyEvent(
            requestedPlacement: placement.name,
            showPlacement: guardPlacement.name,
            eventName: eventName,
            message: _notReadyMessage(guardPolicy, lastError),
          ),
        );
      }
      return AdSequenceShowResult(
        requestedPlacement: placement,
        errorReason: 'no_cache',
      );
    }
    final startedWithoutCommonInventory = initiallyAvailable.isEmpty;
    final firstTarget =
        initiallyAvailable.firstOrNull ?? sequencePlacements.first;
    final secondTarget = sequencePlacements.firstWhere(
      (candidate) => candidate != firstTarget,
    );
    final firstSlot = highValueSlot ?? _cache.firstSlot(firstTarget);
    if (firstSlot == null) {
      return AdSequenceShowResult(
        requestedPlacement: placement,
        errorReason: 'no_cache',
      );
    }
    final usedHighValueFirst =
        highValue != null && firstSlot.placement == highValue;

    _cache.setAttribution(
      firstSlot.ad,
      firstSlot.placement,
      eventName: eventName,
      extras: extras,
    );
    for (final target in sequencePlacements.where((p) => !_cache.hasSlot(p))) {
      unawaited(_loader.preloadPlacement(target, eventName: eventName));
    }
    if (!usedHighValueFirst &&
        highValue != null &&
        !_cache.hasSlot(highValue)) {
      unawaited(_loader.preloadPlacement(highValue, eventName: eventName));
    }

    final firstShown = await _showSlot(
      slot: firstSlot,
      showPlacement: placement,
      policy: adConfig.getPolicy(firstSlot.placement),
      // ignore: use_build_context_synchronously
      context: context,
      eventName: eventName,
      extras: extras,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
    if (!firstShown.shown) {
      if (usedHighValueFirst) {
        unawaited(_loader.preloadPlacement(highValue, eventName: eventName));
      }
      return AdSequenceShowResult(
        requestedPlacement: placement,
        results: [firstShown],
        errorReason: firstShown.errorReason,
      );
    }
    if (startedWithoutCommonInventory) {
      return AdSequenceShowResult(
        requestedPlacement: placement,
        results: [firstShown],
      );
    }

    final secondSlot = usedHighValueFirst
        ? _cache.firstSlot(secondTarget)
        : _highValueOrPlacementSlot(adConfig, secondTarget);
    if (secondSlot == null) {
      return AdSequenceShowResult(
        requestedPlacement: placement,
        results: [firstShown],
      );
    }

    _cache.setAttribution(
      secondSlot.ad,
      secondSlot.placement,
      eventName: eventName,
      extras: extras,
    );
    final usedHighValueSecond =
        highValue != null && secondSlot.placement == highValue;
    if (!usedHighValueSecond) {
      unawaited(
        _loader.preloadPlacement(secondSlot.placement, eventName: eventName),
      );
    }
    final secondShown = await _showSlot(
      slot: secondSlot,
      showPlacement: placement,
      policy: adConfig.getPolicy(secondSlot.placement),
      // ignore: use_build_context_synchronously
      context: context,
      eventName: eventName,
      extras: extras,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
    if (!secondShown.shown && usedHighValueSecond) {
      unawaited(_loader.preloadPlacement(highValue, eventName: eventName));
    }
    return AdSequenceShowResult(
      requestedPlacement: placement,
      results: [firstShown, secondShown],
      errorReason: secondShown.shown ? null : secondShown.errorReason,
    );
  }

  AdSlotLoaded? _highValueOrPlacementSlot(
    AdConfig config,
    PlacementType placement,
  ) {
    final highValue = config.highValuePlacement;
    return (highValue == null ? null : _cache.firstSlot(highValue)) ??
        _cache.firstSlot(placement);
  }

  String _notReadyMessage(PlacementPolicy policy, Object? lastError) {
    final base =
        policy.notReadyMsg ?? 'The ad is not ready, please try again later.';
    if (lastError == null) {
      return base;
    }
    return '$base Last load error: $lastError';
  }

  // --- Native Retrieval ---

  Object? getNativeAd(
    PlacementType placement, {
    String? cacheId,
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    final slot = _cache.firstSlot(placement, cacheId: cacheId);
    if (slot == null) return null;

    _cache.setAttribution(
      slot.ad,
      placement,
      eventName: eventName,
      extras: extras,
    );
    _reportRetrieval(slot, eventName: eventName, extras: extras);
    return slot.ad;
  }

  List<Object> getNativeAds(
    PlacementType placement, {
    int count = 2,
    String? cacheId,
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    final slots = _cache
        .getSlots(placement, cacheId: cacheId)
        .take(count)
        .toList();
    for (final slot in slots) {
      _cache.setAttribution(
        slot.ad,
        placement,
        eventName: eventName,
        extras: extras,
      );
      _reportRetrieval(slot, eventName: eventName, extras: extras);
    }
    return slots.map((s) => s.ad).toList();
  }

  // --- Banner Retrieval ---

  Object? getBannerAd(
    PlacementType placement, {
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    final slot = _cache.firstSlot(placement);
    if (slot == null) return null;
    _cache.setAttribution(
      slot.ad,
      placement,
      eventName: eventName,
      extras: extras,
    );
    _reportRetrieval(slot, eventName: eventName, extras: extras);
    return slot.ad;
  }

  List<Object> getBannerAds(
    PlacementType placement, {
    int count = 2,
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    final slots = _cache.getSlots(placement).take(count).toList();
    for (final slot in slots) {
      _cache.setAttribution(
        slot.ad,
        placement,
        eventName: eventName,
        extras: extras,
      );
      _reportRetrieval(slot, eventName: eventName, extras: extras);
    }
    return slots.map((s) => s.ad).toList();
  }

  void disposeBannerAd(PlacementType placement) {
    final slots = List<AdSlotLoaded>.of(_cache.getSlots(placement));
    for (final slot in slots) {
      _adapterRegistry.dispose(slot.source, slot.type, slot.ad);
    }
    _cache.clear(placement);
  }

  void disposeNativeAd(PlacementType placement, {String? cacheId}) {
    final slots = List<AdSlotLoaded>.of(
      _cache.getSlots(placement, cacheId: cacheId),
    );
    for (final slot in slots) {
      _adapterRegistry.dispose(slot.source, slot.type, slot.ad);
    }
    _cache.clear(placement, cacheId: cacheId);
  }

  // --- Internal ---

  Future<AdShowResult> _showSlot({
    required AdSlotLoaded slot,
    required PlacementType showPlacement,
    required PlacementPolicy policy,
    BuildContext? context,
    required String eventName,
    Map<String, dynamic>? extras,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
  }) async {
    _cache.setAttribution(
      slot.ad,
      slot.placement,
      eventName: eventName,
      extras: extras,
    );
    final adapter = _adapterRegistry.tryGet(slot.source, slot.type);
    if (adapter == null) {
      _guard.markShowFailed(slot.placement, policy);
      _cache.removeSlot(slot.placement, slot);
      return _slotFailure(slot, showPlacement, errorReason: 'missing_adapter');
    }

    final callback = _showCallback(
      requestedPlacement: showPlacement,
      eventName: eventName,
      extras: extras,
      slot: slot,
    );

    _guard.markShowStarted(slot.placement, policy);
    _reportEvent(
      AdEventType.show,
      slot.placement,
      slot.type,
      slot.source,
      slot.adUnitId,
      eventName: eventName,
      extras: extras,
      requestedPlacement: showPlacement,
    );

    if (adapter is! FullscreenAdAdapter) {
      _guard.markShowFailed(slot.placement, policy);
      _adapterRegistry.dispose(slot.source, slot.type, slot.ad);
      _cache.removeSlot(slot.placement, slot);
      return _slotFailure(
        slot,
        showPlacement,
        errorReason: 'unsupported_fullscreen_adapter',
      );
    }

    final result = await adapter.show(
      placement: showPlacement,
      context: context,
      eventName: eventName,
      ad: slot.ad,
      onAdShowed: onAdShowed,
      onClosed: () {
        _cache.removeSlot(slot.placement, slot);
        unawaited(_loader.preload(slot.placement, eventName: eventName));
      },
      closePassThroughPercent: closePassThroughPercent ?? 0,
      onCallback: callback,
    );

    if (result.shown) {
      _guard.markShowCompleted(slot.placement);
    } else {
      _logger.v(
        '❌ [show] failed: showPlacement=${showPlacement.name} '
        'cachePlacement=${slot.placement.name} id=${slot.adUnitId} '
        'error=${result.error}',
      );
      _guard.markShowFailed(slot.placement, policy);
      _cache.removeSlot(slot.placement, slot);
    }
    return result.shown
        ? _slotSuccess(slot, showPlacement)
        : _slotFailure(
            slot,
            showPlacement,
            error: result.error,
            errorReason: result.errorReason ?? 'show_failed',
          );
  }

  AdShowResult _slotSuccess(
    AdSlotLoaded slot,
    PlacementType requestedPlacement,
  ) {
    return AdShowResult.success(
      requestedPlacement: requestedPlacement,
      shownPlacement: slot.placement,
      source: slot.source,
      type: slot.type,
      adUnitId: slot.adUnitId,
    );
  }

  AdShowResult _slotFailure(
    AdSlotLoaded slot,
    PlacementType requestedPlacement, {
    Object? error,
    required String errorReason,
  }) {
    return AdShowResult.failure(
      error: error,
      requestedPlacement: requestedPlacement,
      shownPlacement: slot.placement,
      source: slot.source,
      type: slot.type,
      adUnitId: slot.adUnitId,
      errorReason: errorReason,
    );
  }

  void Function(AdRawCallback) _showCallback({
    required PlacementType requestedPlacement,
    required String eventName,
    Map<String, dynamic>? extras,
    required AdSlotLoaded slot,
  }) {
    return (callback) {
      final event = _eventMapper.map(
        callback,
        placement: slot.placement,
        eventName: eventName,
        extras: extras,
        adType: slot.type,
        source: slot.source,
        adUnitId: slot.adUnitId,
      );
      final attributedEvent = AdEvent(
        eventType: event.eventType,
        requestedPlacement: requestedPlacement,
        placement: event.placement,
        adType: event.adType,
        source: event.source,
        adUnitId: event.adUnitId,
        revenue: event.revenue,
        currency: event.currency,
        rewardAmount: event.rewardAmount,
        rewardLabel: event.rewardLabel,
        errorCode: event.errorCode,
        errorReason: event.errorReason,
        timestamp: event.timestamp,
        eventName: event.eventName,
        extras: event.extras,
        network: event.network,
      );
      _reporter.report(attributedEvent);
      _logger.event(attributedEvent);
    };
  }

  void _reportRetrieval(
    AdSlotLoaded slot, {
    required String eventName,
    Map<String, dynamic>? extras,
  }) {
    _reportEvent(
      AdEventType.show,
      slot.placement,
      slot.type,
      slot.source,
      slot.adUnitId,
      eventName: eventName,
      extras: extras,
    );
  }

  void _reportShowFail({
    required PlacementType placement,
    required String eventName,
    Map<String, dynamic>? extras,
    required String errorReason,
  }) {
    _reportEvent(
      AdEventType.show,
      placement,
      null,
      null,
      null,
      eventName: eventName,
      extras: extras,
    );
    _reportEvent(
      AdEventType.showFail,
      placement,
      null,
      null,
      null,
      errorReason: errorReason,
      eventName: eventName,
      extras: extras,
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
    Map<String, dynamic>? extras,
    PlacementType? requestedPlacement,
  }) {
    final event = AdEvent(
      eventType: type,
      requestedPlacement: requestedPlacement,
      placement: p,
      adType: t,
      source: s,
      adUnitId: id,
      errorReason: errorReason,
      timestamp: DateTime.now(),
      eventName: eventName,
      extras: extras,
    );
    _logger.event(event);
    _reporter.report(event);
  }
}
