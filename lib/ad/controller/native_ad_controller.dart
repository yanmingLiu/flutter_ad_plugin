import 'dart:async';

import '../analytics/ad_event.dart';
import '../analytics/ad_event_reporter.dart';
import '../config/ad_config_repository.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../sdk/ad_adapter_registry.dart';
import '../../tools/log_tool.dart';

class NativeAdController {
  NativeAdController({
    required this.configRepository,
    required this.adapterRegistry,
    required this.reporter,
  });

  final AdConfigRepository configRepository;
  final AdAdapterRegistry adapterRegistry;
  final AdEventReporter reporter;

  final Map<PlacementType, PlacementAdSlot> _slots = {};
  final Map<PlacementType, Timer> _refreshTimers = {};

  void handleLateAd({
    required PlacementType placement,
    required Object ad,
    required AdType type,
    required String adUnitId,
  }) {
    final current = _slots[placement];
    if (current?.hasAd == true) {
      log.d('📥 [late_load] discard: native:${placement.name}');
      _disposeRawAd(ad, AdSource.admob, type);
      return;
    }

    log.d('📥 [late_load] accept: native:${placement.name} ($adUnitId)');
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

  Future<bool> preload(PlacementType placement) async {
    final current = _slots[placement];
    if (current?.isLoading == true) {
      log.d('📥 [preload] skip: native:${placement.name} (loading)');
      return false;
    }
    if (current?.ad != null) {
      log.d('📥 [preload] skip: native:${placement.name} (has cache)');
      return true;
    }

    log.d('📥 [preload] start: native:${placement.name}');
    _slots[placement] = PlacementAdSlot(placement: placement, isLoading: true);
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

    log.d('📥 [preload] units=${units.length}: native:${placement.name}');

    for (final unit in units) {
      log.d('📥 [preload] try: native:${placement.name} id=${unit.id}');
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
        _scheduleRefresh(placement, unit.refreshMinutes);
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
        log.d('✅ [preload] success: native:${placement.name}');
        return true;
      }
      log.d('❌ [preload] fail: native:${placement.name} id=${unit.id}');
    }

    _slots[placement] = PlacementAdSlot(placement: placement);
    log.d('❌ [preload] exhausted: native:${placement.name}');
    return false;
  }

  Object? getAd(PlacementType placement) {
    return _slots[placement]?.ad;
  }

  Future<Object?> show(
    PlacementType placement, {
    String? placementLabel,
  }) async {
    final slot = _slots[placement];
    final ad = slot?.ad;
    final adUnitId = slot?.adUnitId ?? '';
    final placementValue = placementLabel ?? placement.name;

    log.d('🚀 [show] request: native:$placementValue (cache=${ad != null})');

    reporter.report(
      AdEvent(
        eventType: AdEventType.show,
        placement: placement,
        placementLabel: placementLabel,
        adType: AdType.native,
        source: AdSource.admob,
        adUnitId: adUnitId,
        timestamp: DateTime.now(),
      ),
    );

    if (ad == null) {
      log.d('❌ [show] fail: native:$placementValue (no cache)');
      reporter.report(
        AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: AdType.native,
          source: AdSource.admob,
          adUnitId: adUnitId,
          errorCode: -1,
          errorReason: 'no cache',
          timestamp: DateTime.now(),
        ),
      );
      return null;
    }

    reporter.report(
      AdEvent(
        eventType: AdEventType.showSuccess,
        placement: placement,
        placementLabel: placementLabel,
        adType: AdType.native,
        source: AdSource.admob,
        adUnitId: adUnitId,
        timestamp: DateTime.now(),
      ),
    );

    log.d('✅ [show] success: native:$placementValue');

    return ad;
  }

  bool hasAvailableAd(PlacementType placement) => _slots[placement]?.ad != null;

  void clear(PlacementType placement) {
    _refreshTimers.remove(placement)?.cancel();
    final slot = _slots.remove(placement);
    if (slot != null) {
      log.d('🗑️ [clear] native:${placement.name}');
    }
    if (slot?.ad != null &&
        slot?.loadedType != null &&
        slot?.loadedSource != null) {
      _disposeRawAd(slot!.ad!, slot.loadedSource!, slot.loadedType!);
    }
  }

  void dispose() {
    for (final placement in _slots.keys.toList()) {
      clear(placement);
    }
  }

  void _scheduleRefresh(PlacementType placement, int? refreshMinutes) {
    _refreshTimers.remove(placement)?.cancel();
    final minutes = refreshMinutes ?? 40;
    log.d('⏳ [refresh] schedule: native:${placement.name} (${minutes}m)');
    _refreshTimers[placement] = Timer(Duration(minutes: minutes), () {
      log.d('⏳ [refresh] trigger: native:${placement.name}');
      clear(placement);
      preload(placement);
    });
  }
}
