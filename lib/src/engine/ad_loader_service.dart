import 'dart:async';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../platform/ad_callback.dart';
import '../platform/ad_registry.dart';
import '../utils/ad_logger.dart';
import '../utils/ad_reporter.dart';
import '../utils/cancellation_token.dart';
import 'ad_cache_service.dart';
import 'ad_event_mapper.dart';

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

  AdLoaderService({
    required AdConfigRepository configRepository,
    required AdAdapterRegistry adapterRegistry,
    required AdCacheService cache,
    required AdEventMapper eventMapper,
    required AdEventReporter reporter,
  }) : _configRepo = configRepository,
       _adapterRegistry = adapterRegistry,
       _cache = cache,
       _eventMapper = eventMapper,
       _reporter = reporter;

  // --- Loading future dedup ---
  final Map<PlacementType, Future<bool>> _fullscreenLoadingFutures = {};
  final Map<_NativeLoadScope, Future<bool>> _nativeLoadingFutures = {};
  final Map<PlacementType, Future<bool>> _bannerLoadingFutures = {};

  CancellationToken? _cancellationToken;

  void dispose() {
    _cancellationToken?.cancel();
    _fullscreenLoadingFutures.clear();
    _nativeLoadingFutures.clear();
    _bannerLoadingFutures.clear();
  }

  // --- Public API ---

  Future<bool> preload(
    PlacementType placement, {
    required String eventName,
  }) async {
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
    final config = await _configRepo.getConfig();
    final list = placements.toSet();

    for (final p in list) {
      final policy = config.getPolicy(p);
      final units = config.getUnits(p);

      if (units.any(
        (u) =>
            u.type.isFullscreen ||
            (policy.isFullscreen && u.type == AdType.native),
      )) {
        unawaited(preload(p, eventName: eventName));
      }
      if (units.any(
        (u) =>
            u.type.isNative && (!policy.isFullscreen || u.type.isDoubleNative),
      )) {
        unawaited(preloadNative(p, eventName: eventName));
      }
      if (units.any((u) => u.type.isBanner)) {
        unawaited(preloadBanner(p, eventName: eventName));
      }
    }
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
      log.v(
        '📥 [preload] exhausted: placement=${placement.name} '
        'reason=no_units event=$eventName',
      );
      return false;
    }

    _cache.beginLoading(placement, cacheId: cacheId);
    final loadedSlots = <AdSlotLoaded>[];
    Object? lastError;

    final ct = _cancellationToken;

    for (final unit in units) {
      if (ct?.isCancelled ?? false) break;

      _reportEvent(
        AdEventType.loadRequested,
        placement,
        unit.type,
        unit.source,
        unit.id,
        eventName: eventName,
      );

      final adapterType = adapterTypeFor(unit);
      final adapter = _adapterRegistry.get(unit.source, adapterType);

      final result = await adapter.load(
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

        if (loadedSlots.length >= targetCount) {
          _cache.commitSlots(placement, loadedSlots, cacheId: cacheId);
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
        loadedSlots.length < requiredDoubleNativeCount) {
      for (final slot in loadedSlots) {
        _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
        _cache.removeAttribution(slot.ad);
      }
      _cache.commitSlots(
        placement,
        const [],
        lastError: lastError ?? 'double_native_incomplete',
        cacheId: cacheId,
      );
      return false;
    }

    _cache.commitSlots(
      placement,
      loadedSlots,
      lastError: lastError,
      cacheId: cacheId,
    );

    if (loadedSlots.isEmpty) {
      log.v(
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
    if (_cache.hasSlotWithKey(placement, cacheKey, cacheId: cacheId) ||
        _cache.countFor(placement, cacheId: cacheId) >= targetCount) {
      _adapterRegistry.get(source, type).dispose(ad);
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

      final event = _eventMapper.map(
        callback,
        placement: p,
        eventName: en,
        adType: unit.type,
        source: unit.source,
        adUnitId: unit.id,
      );
      _reporter.report(event);
      log.event(event);
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
    log.event(event);
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
