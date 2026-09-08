import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../core/ad_policy.dart';
import '../platform/ad_callback.dart';
import '../platform/ad_registry.dart';
import '../ui/fullscreen_native_ad_dialog.dart';
import '../utils/ad_logger.dart';
import '../utils/ad_reporter.dart';
import 'ad_cache_service.dart';
import 'ad_event_mapper.dart';
import 'ad_guard.dart';
import 'ad_loader_service.dart';

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

  AdPresenter({
    required AdConfigRepository configRepository,
    required AdAdapterRegistry adapterRegistry,
    required AdCacheService cache,
    required AdDisplayGuard guard,
    required AdEventMapper eventMapper,
    required AdEventReporter reporter,
    required AdLoaderService loader,
  }) : _configRepo = configRepository,
       _adapterRegistry = adapterRegistry,
       _cache = cache,
       _guard = guard,
       _eventMapper = eventMapper,
       _reporter = reporter,
       _loader = loader;

  // --- Fullscreen Show ---

  Future<AdShowResult> show(
    PlacementType placement, {
    BuildContext? context,
    required String eventName,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
    AdNotReadyCallback? onAdNotReady,
  }) async {
    final adConfig = await _configRepo.getConfig();
    final poolPlacements = _fullscreenPoolPlacements(adConfig, placement);
    final guardPlacement = poolPlacements.first;
    final guardPolicy = adConfig.getPolicy(guardPlacement);

    log.v(
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
      log.v(
        '🚫 [show] blocked: event=$eventName '
        'reason=${guardResult.reason?.name}',
      );
      _reportShowFail(
        placement: placement,
        eventName: eventName,
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
      log.v(
        '❌ [show] failed: reason=no_cache '
        'request=${placement.name} '
        'lastError=$lastError',
      );
      _reportShowFail(
        placement: placement,
        eventName: eventName,
        errorReason: 'no_cache',
      );
      unawaited(_loader.preload(placement, eventName: eventName));
      if (guardPolicy.showNotReadyToast && onAdNotReady != null) {
        onAdNotReady(
          AdNotReadyEvent(
            requestedPlacement: placement,
            showPlacement: guardPlacement,
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
  Future<bool> showSequence(
    PlacementType placement, {
    BuildContext? context,
    required String eventName,
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
      return (await show(
        placement,
        // ignore: use_build_context_synchronously
        context: context,
        eventName: eventName,
        onAdShowed: onAdShowed,
        closePassThroughPercent: closePassThroughPercent,
        onAdNotReady: onAdNotReady,
      )).shown;
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
        errorReason: _guardErrorReason(guardResult),
      );
      return false;
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
        errorReason: 'no_cache',
      );
      for (final target in sequencePlacements) {
        unawaited(_loader.preloadPlacement(target, eventName: eventName));
      }
      if (guardPolicy.showNotReadyToast && onAdNotReady != null) {
        onAdNotReady(
          AdNotReadyEvent(
            requestedPlacement: placement,
            showPlacement: guardPlacement,
            eventName: eventName,
            message: _notReadyMessage(guardPolicy, lastError),
          ),
        );
      }
      return false;
    }
    final startedWithoutCommonInventory = initiallyAvailable.isEmpty;
    final firstTarget =
        initiallyAvailable.firstOrNull ?? sequencePlacements.first;
    final secondTarget = sequencePlacements.firstWhere(
      (candidate) => candidate != firstTarget,
    );
    final firstSlot = highValueSlot ?? _cache.firstSlot(firstTarget);
    if (firstSlot == null) return false;
    final usedHighValueFirst =
        highValue != null && firstSlot.placement == highValue;

    _cache.removeSlot(firstSlot.placement, firstSlot);
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
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
    if (!firstShown.shown) {
      if (usedHighValueFirst) {
        unawaited(_loader.preloadPlacement(highValue, eventName: eventName));
      }
      return false;
    }
    if (startedWithoutCommonInventory) return true;

    final secondSlot = usedHighValueFirst
        ? _cache.firstSlot(secondTarget)
        : _highValueOrPlacementSlot(adConfig, secondTarget);
    if (secondSlot == null) return true;

    _cache.removeSlot(secondSlot.placement, secondSlot);
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
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
    if (!secondShown.shown && usedHighValueSecond) {
      unawaited(_loader.preloadPlacement(highValue, eventName: eventName));
    }
    return secondShown.shown;
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
  }) {
    final slot = _cache.firstSlot(placement, cacheId: cacheId);
    if (slot == null) return null;

    _cache.setAttribution(slot.ad, placement, eventName: eventName);
    _reportRetrieval(slot, eventName: eventName);
    return slot.ad;
  }

  List<Object> getNativeAds(
    PlacementType placement, {
    int count = 2,
    String? cacheId,
    required String eventName,
  }) {
    final slots = _cache
        .getSlots(placement, cacheId: cacheId)
        .take(count)
        .toList();
    for (final slot in slots) {
      _cache.setAttribution(slot.ad, placement, eventName: eventName);
      _reportRetrieval(slot, eventName: eventName);
    }
    return slots.map((s) => s.ad).toList();
  }

  // --- Banner Retrieval ---

  Object? getBannerAd(PlacementType placement) {
    return _cache.firstSlot(placement)?.ad;
  }

  List<Object> getBannerAds(
    PlacementType placement, {
    int count = 2,
    required String eventName,
  }) {
    final slots = _cache.getSlots(placement).take(count).toList();
    for (final slot in slots) {
      _cache.setAttribution(slot.ad, placement, eventName: eventName);
      _reportRetrieval(slot, eventName: eventName);
    }
    return slots.map((s) => s.ad).toList();
  }

  void disposeBannerAd(PlacementType placement) {
    final slots = List<AdSlotLoaded>.of(_cache.getSlots(placement));
    for (final slot in slots) {
      _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
    }
    _cache.clear(placement);
  }

  void disposeNativeAd(PlacementType placement, {String? cacheId}) {
    final slots = List<AdSlotLoaded>.of(
      _cache.getSlots(placement, cacheId: cacheId),
    );
    for (final slot in slots) {
      _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
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
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
  }) async {
    final adapter = _adapterRegistry.get(slot.source, slot.type);
    final callback = _showCallback(
      requestedPlacement: showPlacement,
      eventName: eventName,
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
      requestedPlacement: showPlacement,
    );

    if (slot.type == AdType.native && policy.isFullscreen) {
      if (context == null) {
        callback(AdShowFailedCallback(slot.ad, null, 'missing_context', null));
        _guard.markShowFailed(slot.placement, policy);
        _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
        _cache.removeSlot(slot.placement, slot);
        return _slotFailure(
          slot,
          showPlacement,
          errorReason: 'missing_context',
        );
      }

      final result = await adapter.show(
        placement: showPlacement,
        context: context,
        eventName: eventName,
        ad: slot.ad,
        onAdShowed: onAdShowed,
        closePassThroughPercent: closePassThroughPercent ?? 0,
        onCallback: callback,
      );

      if (!result.shown) {
        log.v(
          '❌ [show] failed: showPlacement=${showPlacement.name} '
          'cachePlacement=${slot.placement.name} id=${slot.adUnitId} '
          'error=${result.error}',
        );
        _guard.markShowFailed(slot.placement, policy);
        _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
        _cache.removeSlot(slot.placement, slot);
        return _slotFailure(
          slot,
          showPlacement,
          error: result.error,
          errorReason: result.errorReason ?? 'show_failed',
        );
      }

      final dialogShown = await FullscreenNativeAdDialog.show(
        // ignore: use_build_context_synchronously
        context: context,
        placement: showPlacement,
        eventName: eventName,
        ad: slot.ad,
        clickTracker: adapter is NativeAdClickTracker
            ? adapter as NativeAdClickTracker
            : null,
        closePassThroughPercent: closePassThroughPercent ?? 0,
        onClosed: () {
          callback(AdClosedCallback(slot.ad, null));
          _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
          _cache.removeSlot(slot.placement, slot);
          unawaited(_loader.preload(slot.placement, eventName: eventName));
        },
      );

      if (dialogShown) {
        _guard.markShowCompleted(slot.placement);
        return _slotSuccess(slot, showPlacement);
      }

      callback(AdShowFailedCallback(slot.ad, -1, 'dialog_exists', null));
      _guard.markShowFailed(slot.placement, policy);
      return _slotFailure(slot, showPlacement, errorReason: 'dialog_exists');
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
      log.v(
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
    required AdSlotLoaded slot,
  }) {
    return (callback) {
      final event = _eventMapper.map(
        callback,
        placement: slot.placement,
        eventName: eventName,
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
        errorCode: event.errorCode,
        errorReason: event.errorReason,
        timestamp: event.timestamp,
        eventName: event.eventName,
        network: event.network,
      );
      _reporter.report(attributedEvent);
      log.event(attributedEvent);
    };
  }

  void _reportRetrieval(AdSlotLoaded slot, {required String eventName}) {
    _reportEvent(
      AdEventType.show,
      slot.placement,
      slot.type,
      slot.source,
      slot.adUnitId,
      eventName: eventName,
    );
  }

  void _reportShowFail({
    required PlacementType placement,
    required String eventName,
    required String errorReason,
  }) {
    _reportEvent(
      AdEventType.show,
      placement,
      null,
      null,
      null,
      eventName: eventName,
    );
    _reportEvent(
      AdEventType.showFail,
      placement,
      null,
      null,
      null,
      errorReason: errorReason,
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
    );
    log.event(event);
    _reporter.report(event);
  }
}
