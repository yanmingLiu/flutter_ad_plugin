import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../core/ad_policy.dart';
import '../api/fullscreen_native_presenter.dart';
import '../platform/ad_callback.dart';
import '../platform/ad_registry.dart';
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
  final AppLogger _logger;
  final FullscreenNativeAdPresenter? _fullscreenNativePresenter;

  AdPresenter({
    required AdConfigRepository configRepository,
    required AdAdapterRegistry adapterRegistry,
    required AdCacheService cache,
    required AdDisplayGuard guard,
    required AdEventMapper eventMapper,
    required AdEventReporter reporter,
    required AdLoaderService loader,
    AppLogger? logger,
    FullscreenNativeAdPresenter? fullscreenNativePresenter,
  }) : _configRepo = configRepository,
       _adapterRegistry = adapterRegistry,
       _cache = cache,
       _guard = guard,
       _eventMapper = eventMapper,
       _reporter = reporter,
       _loader = loader,
       _logger = logger ?? log,
       _fullscreenNativePresenter = fullscreenNativePresenter;

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
  Future<AdSequenceShowResult> showSequence(
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
      final result = await show(
        placement,
        // ignore: use_build_context_synchronously
        context: context,
        eventName: eventName,
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

  Object? getBannerAd(PlacementType placement, {required String eventName}) {
    final slot = _cache.firstSlot(placement);
    if (slot == null) return null;
    _cache.setAttribution(slot.ad, placement, eventName: eventName);
    _reportRetrieval(slot, eventName: eventName);
    return slot.ad;
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
    _cache.setAttribution(slot.ad, slot.placement, eventName: eventName);
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

      final fullscreenNativePresenter = _fullscreenNativePresenter;
      if (fullscreenNativePresenter == null) {
        callback(
          AdShowFailedCallback(
            slot.ad,
            null,
            'missing_fullscreen_native_presenter',
            null,
          ),
        );
        _guard.markShowFailed(slot.placement, policy);
        adapter.dispose(slot.ad);
        _cache.removeSlot(slot.placement, slot);
        return _slotFailure(
          slot,
          showPlacement,
          errorReason: 'missing_fullscreen_native_presenter',
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
        _logger.v(
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

      bool dialogShown;
      var closed = false;
      void handleClosed() {
        if (closed) return;
        closed = true;
        callback(AdClosedCallback(slot.ad, null));
        _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
        _cache.removeSlot(slot.placement, slot);
        unawaited(_loader.preload(slot.placement, eventName: eventName));
      }

      try {
        dialogShown = await fullscreenNativePresenter(
          // ignore: use_build_context_synchronously
          context: context,
          placement: showPlacement,
          eventName: eventName,
          ad: slot.ad,
          clickTracker: adapter is NativeAdClickTracker
              ? adapter as NativeAdClickTracker
              : null,
          closePassThroughPercent: closePassThroughPercent ?? 0,
          onClosed: handleClosed,
        );
      } catch (error) {
        callback(AdShowFailedCallback(slot.ad, null, error.toString(), null));
        _guard.markShowFailed(slot.placement, policy);
        adapter.dispose(slot.ad);
        _cache.removeSlot(slot.placement, slot);
        return _slotFailure(
          slot,
          showPlacement,
          error: error,
          errorReason: 'fullscreen_native_presenter_failed',
        );
      }

      if (dialogShown) {
        handleClosed();
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
      _logger.event(attributedEvent);
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
    _logger.event(event);
    _reporter.report(event);
  }
}
