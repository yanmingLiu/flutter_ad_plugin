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
import 'ad_lifecycle_manager.dart';
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

  Future<bool> show(
    PlacementType placement, {
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
    AdNotReadyCallback? onAdNotReady,
  }) async {
    final adConfig = await _configRepo.getConfig();
    final showPlacement = _resolveShowPlacement(adConfig, placement);
    final isFallback = showPlacement != placement;
    final policy = adConfig.getPolicy(showPlacement);
    final preferHighValue = !isFallback && policy.preferHighValueOnShow;

    log.v(
      '🚀 [show] request=${placement.name} '
      'label=${placementLabel ?? placement.name} show=${showPlacement.name} '
      'commonResolved=$isFallback event=$eventName '
      'waitForLoad=${policy.waitForLoadOnShow}',
    );

    // Guard check
    final guardResult = await _guard.canShow(
      placement: showPlacement,
      configRepository: _configRepo,
    );
    if (!guardResult.allowed) {
      log.v(
        '🚫 [show] blocked: ${placementLabel ?? placement.name} '
        'reason=${guardResult.reason?.name}',
      );
      _reportShowFail(
        placement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        errorReason: 'guard_blocked: ${guardResult.reason?.name ?? 'unknown'}',
      );
      return false;
    }

    // Try preload if cache empty and policy allows
    if (!_cache.hasSlot(showPlacement) && policy.waitForLoadOnShow) {
      log.v(
        '📥 [show] no_cache, try_preload: placement=${showPlacement.name} '
        'event=$eventName',
      );
      await _loader.preload(showPlacement, eventName: eventName);
    }

    // Select slot
    final slot = _selectSlot(
      config: adConfig,
      showPlacement: showPlacement,
      preferHighValue: preferHighValue,
    );

    if (slot == null) {
      final lastError = _cache.lastErrorFor(showPlacement);
      log.v(
        '❌ [show] failed: reason=no_cache '
        'request=${placement.name} show=${showPlacement.name} '
        'lastError=$lastError',
      );
      _reportShowFail(
        placement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        errorReason: 'no_cache',
      );
      if (policy.showNotReadyToast && onAdNotReady != null) {
        onAdNotReady(
          AdNotReadyEvent(
            requestedPlacement: placement,
            showPlacement: showPlacement,
            placementLabel: placementLabel,
            eventName: eventName,
            message: _notReadyMessage(policy, lastError),
          ),
        );
      }
      return false;
    }

    return _showSlot(
      slot: slot,
      showPlacement: showPlacement,
      policy: policy,
      // ignore: use_build_context_synchronously
      context: context,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
  }

  /// Shows two fullscreen ads sequentially from the same placement cache.
  Future<bool> showSequence(
    PlacementType placement, {
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
    AdNotReadyCallback? onAdNotReady,
  }) async {
    final adConfig = await _configRepo.getConfig();
    final showPlacement = _resolveShowPlacement(adConfig, placement);
    final policy = adConfig.getPolicy(showPlacement);

    if (!_cache.hasSlot(showPlacement) && policy.waitForLoadOnShow) {
      await _loader.preload(showPlacement, eventName: eventName);
    }

    final firstSlot = _selectSlot(
      config: adConfig,
      showPlacement: showPlacement,
      preferHighValue: showPlacement != placement,
    );
    if (firstSlot == null) {
      final lastError = _cache.lastErrorFor(showPlacement);
      _reportShowFail(
        placement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        errorReason: 'no_cache',
      );
      if (policy.showNotReadyToast && onAdNotReady != null) {
        onAdNotReady(
          AdNotReadyEvent(
            requestedPlacement: placement,
            showPlacement: showPlacement,
            placementLabel: placementLabel,
            eventName: eventName,
            message: _notReadyMessage(policy, lastError),
          ),
        );
      }
      return false;
    }

    final secondSlot = _selectSlot(
      config: adConfig,
      showPlacement: showPlacement,
      excludedSlots: {firstSlot},
      preferHighValue: showPlacement != placement,
    );

    if (secondSlot == null) {
      log.v(
        '📥 [show_sequence] missing second slot: '
        'placement=${showPlacement.name} event=$eventName',
      );
      final refillFuture = _loader.preload(showPlacement, eventName: eventName);
      final firstShown = await _showSlot(
        slot: firstSlot,
        showPlacement: showPlacement,
        policy: policy,
        // ignore: use_build_context_synchronously
        context: context,
        placementLabel: placementLabel,
        eventName: eventName,
        onAdShowed: onAdShowed,
        closePassThroughPercent: closePassThroughPercent,
      );
      if (!firstShown) return false;

      await refillFuture;
      final refilledSlot = _selectSlot(
        config: await _configRepo.getConfig(),
        showPlacement: showPlacement,
        preferHighValue: showPlacement != placement,
      );
      if (refilledSlot == null) return true;

      await _showSlot(
        slot: refilledSlot,
        showPlacement: showPlacement,
        policy: policy,
        // ignore: use_build_context_synchronously
        context: context,
        placementLabel: placementLabel,
        eventName: eventName,
        onAdShowed: onAdShowed,
        closePassThroughPercent: closePassThroughPercent,
      );
      return true;
    }

    final firstShown = await _showSlot(
      slot: firstSlot,
      showPlacement: showPlacement,
      policy: policy,
      // ignore: use_build_context_synchronously
      context: context,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
    if (!firstShown) return false;

    return _showSlot(
      slot: secondSlot,
      showPlacement: showPlacement,
      policy: policy,
      // ignore: use_build_context_synchronously
      context: context,
      placementLabel: placementLabel,
      eventName: eventName,
      onAdShowed: onAdShowed,
      closePassThroughPercent: closePassThroughPercent,
    );
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
    String? placementLabel,
    required String eventName,
  }) {
    final slot = _cache.firstSlot(placement);
    if (slot == null) return null;

    _cache.setAttribution(
      slot.ad,
      placement,
      placementLabel: placementLabel,
      eventName: eventName,
    );
    _reportRetrieval(
      slot,
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
    final slots = _cache.getSlots(placement).take(count).toList();
    for (final slot in slots) {
      _cache.setAttribution(
        slot.ad,
        placement,
        placementLabel: placementLabel,
        eventName: eventName,
      );
      _reportRetrieval(
        slot,
        placementLabel: placementLabel,
        eventName: eventName,
      );
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
    String? placementLabel,
    required String eventName,
  }) {
    final slots = _cache.getSlots(placement).take(count).toList();
    for (final slot in slots) {
      _cache.setAttribution(
        slot.ad,
        placement,
        placementLabel: placementLabel,
        eventName: eventName,
      );
      _reportRetrieval(
        slot,
        placementLabel: placementLabel,
        eventName: eventName,
      );
    }
    return slots.map((s) => s.ad).toList();
  }

  void disposeBannerAd(PlacementType placement) {
    _lifecycle?.cancelRefresh(placement.name);
    final slots = List<AdSlotLoaded>.of(_cache.getSlots(placement));
    for (final slot in slots) {
      _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
    }
    _cache.clear(placement);
  }

  void disposeNativeAd(PlacementType placement) {
    _lifecycle?.cancelRefresh(placement.name);
    final slots = List<AdSlotLoaded>.of(_cache.getSlots(placement));
    for (final slot in slots) {
      _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
    }
    _cache.clear(placement);
  }

  // --- Internal ---

  PlacementType _resolveShowPlacement(
    AdConfig config,
    PlacementType requested,
  ) {
    if (config.hasPlacement(requested)) return requested;
    return config.commonPlacements.firstWhere(
      config.hasPlacement,
      orElse: () => requested,
    );
  }

  AdSlotLoaded? _selectSlot({
    required AdConfig config,
    required PlacementType showPlacement,
    Set<AdSlotLoaded> excludedSlots = const {},
    required bool preferHighValue,
  }) {
    // High-value placement substitution
    if (preferHighValue && config.highValuePlacement != null) {
      final highValueSlot = _cache.firstSlotExcluding(
        config.highValuePlacement!,
        excludedSlots,
      );
      final configuredFirst = _cache.firstSlot(showPlacement);
      if (highValueSlot != null && !(configuredFirst?.type.isNative ?? false)) {
        return highValueSlot;
      }
    }

    return _cache.firstSlotExcluding(showPlacement, excludedSlots);
  }

  Future<bool> _showSlot({
    required AdSlotLoaded slot,
    required PlacementType showPlacement,
    required PlacementPolicy policy,
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    VoidCallback? onAdShowed,
    int? closePassThroughPercent,
  }) async {
    final adapter = _adapterRegistry.get(slot.source, slot.type);
    final callback = _showCallback(
      showPlacement: showPlacement,
      placementLabel: placementLabel,
      eventName: eventName,
      slot: slot,
    );

    _guard.markShowStarted(slot.placement, policy);
    _reportEvent(
      AdEventType.show,
      showPlacement,
      slot.type,
      slot.source,
      slot.adUnitId,
      placementLabel: placementLabel,
      eventName: eventName,
    );

    if (slot.type == AdType.native && policy.isFullscreen) {
      if (context == null) {
        callback(AdShowFailedCallback(slot.ad, null, 'missing_context', null));
        _guard.markShowFailed(slot.placement, policy);
        _adapterRegistry.get(slot.source, slot.type).dispose(slot.ad);
        _cache.removeSlot(slot.placement, slot);
        return false;
      }

      final result = await adapter.show(
        placement: showPlacement,
        context: context,
        placementLabel: placementLabel,
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
        return false;
      }

      final dialogShown = await FullscreenNativeAdDialog.show(
        // ignore: use_build_context_synchronously
        context: context,
        placement: showPlacement,
        placementLabel: placementLabel ?? showPlacement.name,
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
        _guard.markShowCompleted(slot.placement, policy);
        return true;
      }

      callback(AdShowFailedCallback(slot.ad, -1, 'dialog_exists', null));
      _guard.markShowFailed(slot.placement, policy);
      return false;
    }

    final result = await adapter.show(
      placement: showPlacement,
      context: context,
      placementLabel: placementLabel,
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
      _guard.markShowCompleted(slot.placement, policy);
    } else {
      log.v(
        '❌ [show] failed: showPlacement=${showPlacement.name} '
        'cachePlacement=${slot.placement.name} id=${slot.adUnitId} '
        'error=${result.error}',
      );
      _guard.markShowFailed(slot.placement, policy);
      _cache.removeSlot(slot.placement, slot);
    }
    return result.shown;
  }

  void Function(AdRawCallback) _showCallback({
    required PlacementType showPlacement,
    String? placementLabel,
    required String eventName,
    required AdSlotLoaded slot,
  }) {
    return (callback) {
      final event = _eventMapper.map(
        callback,
        placement: showPlacement,
        placementLabel: placementLabel,
        eventName: eventName,
        adType: slot.type,
        source: slot.source,
        adUnitId: slot.adUnitId,
      );
      _reporter.report(event);
      log.event(event);
    };
  }

  void _reportRetrieval(
    AdSlotLoaded slot, {
    String? placementLabel,
    required String eventName,
  }) {
    _reportEvent(
      AdEventType.show,
      slot.placement,
      slot.type,
      slot.source,
      slot.adUnitId,
      placementLabel: placementLabel,
      eventName: eventName,
    );
  }

  void _reportShowFail({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required String errorReason,
  }) {
    _reportEvent(
      AdEventType.show,
      placement,
      null,
      null,
      null,
      placementLabel: placementLabel,
      eventName: eventName,
    );
    _reportEvent(
      AdEventType.showFail,
      placement,
      null,
      null,
      null,
      errorReason: errorReason,
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
    String? placementLabel,
    required String eventName,
  }) {
    final event = AdEvent(
      eventType: type,
      placement: p,
      placementLabel: placementLabel,
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

  AdLifecycleManager? _lifecycle;

  void setLifecycleManager(AdLifecycleManager lifecycle) {
    _lifecycle = lifecycle;
  }
}
