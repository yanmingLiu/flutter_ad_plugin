import 'dart:async';
import 'package:flutter/foundation.dart';

import '../analytics/ad_event.dart';
import '../analytics/ad_event_reporter.dart';
import '../config/ad_config_repository.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../sdk/ad_adapter_registry.dart';
import '../../tools/log_tool.dart';

class FullscreenAdController {
  FullscreenAdController({
    required this.configRepository,
    required this.adapterRegistry,
    required this.reporter,
  });

  final AdConfigRepository configRepository;
  final AdAdapterRegistry adapterRegistry;
  final AdEventReporter reporter;

  final Map<PlacementType, PlacementAdSlot> _slots = {};
  final Map<PlacementType, Future<bool>> _loadingFutures = {};

  void handleLateAd({
    required PlacementType placement,
    required Object ad,
    required AdType type,
    required String adUnitId,
  }) {
    final current = _slots[placement];
    if (current?.hasAd == true) {
      log.d('📥 [late_load] discard: ${placement.name} (already has cache)');
      _disposeRawAd(ad, AdSource.admob, type); // 默认 AdMob，实际应根据 source
      return;
    }

    log.d('📥 [late_load] accept: ${placement.name} ($adUnitId)');
    _slots[placement] = PlacementAdSlot(
      placement: placement,
      ad: ad,
      loadedSource: AdSource.admob,
      loadedType: type,
      adUnitId: adUnitId,
      loadedAt: DateTime.now(),
    );
  }

  void _disposeRawAd(Object ad, AdSource source, AdType type) {
    try {
      adapterRegistry.get(source, type).dispose(ad);
    } catch (_) {}
  }

  PlacementAdSlot? getSlot(PlacementType placement) => _slots[placement];

  bool hasAvailableAd(PlacementType placement) {
    return _slots[placement]?.hasAd ?? false;
  }

  Future<bool> preload(PlacementType placement) async {
    if (_loadingFutures.containsKey(placement)) {
      log.d('📥 [preload] wait: ${placement.name}');
      return await _loadingFutures[placement]!;
    }

    final current = _slots[placement];
    if (current?.hasAd == true) {
      log.d('📥 [preload] skip: ${placement.name} (has cache)');
      return true;
    }

    log.d('📥 [preload] start: ${placement.name}');
    final loadFuture = _performLoad(placement);
    _loadingFutures[placement] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      _loadingFutures.remove(placement);
    }
  }

  Future<bool> _performLoad(PlacementType placement) async {
    _slots[placement] = PlacementAdSlot(placement: placement, isLoading: true);

    try {
      final config = await configRepository.getConfig();
      final policy = config.getPolicy(placement);
      final timeout = Duration(seconds: config.loadTimeoutSeconds);
      final units =
          config
              .getUnits(placement)
              .where((unit) => unit.isValid)
              .where(
                (unit) => policy.supports(unit.type),
              )
              .toList()
            ..sort((a, b) => b.weight.compareTo(a.weight));

      if (units.isEmpty) {
        log.d('📥 [preload] empty: ${placement.name}');
        _slots[placement] = PlacementAdSlot(placement: placement);
        return false;
      }

      log.d('📥 [preload] units=${units.length}: ${placement.name}');

      Object? lastError;
      for (final unit in units) {
        log.d('📥 [preload] try: ${placement.name} type=${unit.type.name} id=${unit.id}');
        reporter.report(
          AdEvent(
            eventType: AdEventType.loadRequested,
            placement: placement,
            adType: unit.type,
            source: unit.source,
            adUnitId: unit.id,
            timestamp: DateTime.now(),
          ),
        );

        final adapter = adapterRegistry.get(unit.source, unit.type);
        final result = await adapter.load(
          placement: placement,
          unit: unit,
          timeout: timeout,
          reporter: reporter,
          onLateAdLoaded: (ad, type, adUnitId) {
            handleLateAd(
              placement: placement,
              ad: ad,
              type: type,
              adUnitId: adUnitId,
            );
          },
        );

        if (result.isSuccess) {
          _slots[placement] = PlacementAdSlot(
            placement: placement,
            ad: result.ad,
            loadedSource: unit.source,
            loadedType: unit.type,
            adUnitId: unit.id,
            loadedAt: DateTime.now(),
          );
          reporter.report(
            AdEvent(
              eventType: AdEventType.loadSucceeded,
              placement: placement,
              adType: unit.type,
              source: unit.source,
              adUnitId: unit.id,
              timestamp: DateTime.now(),
            ),
          );
          log.d('✅ [preload] success: ${placement.name} (${unit.type.name})');
          return true;
        }

        lastError = result.error;
        log.d('❌ [preload] fail: ${placement.name} (${unit.type.name}) error=$lastError');
        reporter.report(
          AdEvent(
            eventType: AdEventType.loadFailed,
            placement: placement,
            adType: unit.type,
            source: unit.source,
            adUnitId: unit.id,
            errorReason: lastError?.toString(),
            timestamp: DateTime.now(),
          ),
        );
      }

      log.d('❌ [preload] exhausted: ${placement.name}');
      _slots[placement] = PlacementAdSlot(
        placement: placement,
        lastError: lastError,
      );
      return false;
    } catch (e) {
      log.e('❌ [preload] fatal: ${placement.name} error=$e');
      _slots[placement] = PlacementAdSlot(placement: placement, lastError: e);
      return false;
    }
  }

  void removeSlot(PlacementType placement) {
    final slot = _slots[placement];
    if (slot != null) {
      log.d('🗑️ [remove_slot] ${placement.name} (${slot.loadedType?.name})');
      if (slot.ad != null) {
        _disposeRawAd(slot.ad!, slot.loadedSource!, slot.loadedType!);
      }
      _slots.remove(placement);
    }
  }

  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    VoidCallback? onAdShowed,
  }) async {
    final slot = _slots[placement];
    if (slot == null || slot.ad == null) {
      return AdShowResult.failure('no_cache');
    }

    final ad = slot.ad!;
    final source = slot.loadedSource!;
    final type = slot.loadedType!;
    final placementValue = placementLabel ?? placement.name;

    log.d('🚀 [show] use_cache: $placementValue type=${type.name}');

    final adapter = adapterRegistry.get(source, type);
    final result = await adapter.show(
      placement: placement,
      placementLabel: placementLabel,
      ad: ad,
      reporter: reporter,
      onAdShowed: onAdShowed,
      onClosed: () {
        log.d('🚪 [show] closed: $placementValue');
        removeSlot(placement);
        unawaited(preload(placement));
      },
    );

    if (result.shown) {
      log.d('✅ [show] success: $placementValue');
    } else {
      log.d('❌ [show] fail: $placementValue error=${result.error}');
      removeSlot(placement);
    }

    return result;
  }
}
