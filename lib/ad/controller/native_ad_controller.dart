import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../analytics/ad_event.dart';
import '../analytics/ad_event_reporter.dart';
import '../config/ad_config_repository.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../core/placement_capabilities.dart';
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

  Future<bool> preload(PlacementType placement) async {
    final current = _slots[placement];
    if (current?.isLoading == true) {
      log.d('[ad][native][preload] skip_loading placement=${placement.name}');
      return false;
    }
    if (current?.ad != null) {
      log.d(
        '[ad][native][preload] skip_has_cache placement=${placement.name} adid=${current?.adUnitId ?? ''}',
      );
      return true;
    }

    log.d('[ad][native][preload] start placement=${placement.name}');
    _slots[placement] = PlacementAdSlot(placement: placement, isLoading: true);
    final config = await configRepository.getConfig();
    final timeout = Duration(seconds: config.loadTimeoutSeconds);
    final units =
        config
            .getUnits(placement)
            .where((unit) => unit.isValid)
            .where(
              (unit) => PlacementCapabilities.supports(placement, unit.type),
            )
            .toList()
          ..sort((a, b) => b.weight.compareTo(a.weight));

    log.d(
      '[ad][native][preload] candidates placement=${placement.name} count=${units.length}',
    );

    for (final unit in units) {
      log.d(
        '[ad][native][preload] try placement=${placement.name} type=${unit.type.name} adid=${unit.id} weight=${unit.weight}',
      );
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
        _scheduleRefresh(placement);
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
        log.d(
          '[ad][native][preload] success placement=${placement.name} type=${unit.type.name} adid=${unit.id}',
        );
        return true;
      }
      log.d(
        '[ad][native][preload] fail placement=${placement.name} type=${unit.type.name} adid=${unit.id} error=${result.error}',
      );
    }

    _slots[placement] = PlacementAdSlot(placement: placement);
    log.d('[ad][native][preload] exhausted placement=${placement.name}');
    return false;
  }

  NativeAd? getAd(PlacementType placement) {
    return _slots[placement]?.ad as NativeAd?;
  }

  Future<NativeAd?> show(
    PlacementType placement, {
    String? placementLabel,
  }) async {
    final slot = _slots[placement];
    final ad = slot?.ad as NativeAd?;
    final adUnitId = slot?.adUnitId ?? '';
    final placementValue = placementLabel ?? placement.name;

    log.d(
      '[ad][native][show] request placement=$placementValue adid=$adUnitId hasCache=${ad != null}',
    );

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
      log.d('[ad][native][show] fail_no_cache placement=$placementValue');
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

    log.d(
      '[ad][native][show] success placement=$placementValue adid=$adUnitId',
    );

    return ad;
  }

  bool hasAvailableAd(PlacementType placement) => _slots[placement]?.ad != null;

  void clear(PlacementType placement) {
    _refreshTimers.remove(placement)?.cancel();
    final slot = _slots.remove(placement);
    if (slot != null) {
      log.d(
        '[ad][native][clear] placement=${placement.name} source=${slot.loadedSource?.name ?? ''} type=${slot.loadedType?.name ?? ''} adid=${slot.adUnitId ?? ''}',
      );
    }
    if (slot?.ad != null &&
        slot?.loadedType != null &&
        slot?.loadedSource != null) {
      final adapter = adapterRegistry.get(
        slot!.loadedSource!,
        slot.loadedType!,
      );
      adapter.dispose(slot.ad!);
    }
  }

  void dispose() {
    for (final placement in _slots.keys.toList()) {
      clear(placement);
    }
  }

  void _scheduleRefresh(PlacementType placement) {
    _refreshTimers.remove(placement)?.cancel();
    log.d(
      '[ad][native][refresh] schedule placement=${placement.name} delay=40m',
    );
    _refreshTimers[placement] = Timer(const Duration(minutes: 40), () {
      log.d('[ad][native][refresh] trigger placement=${placement.name}');
      clear(placement);
      preload(placement);
    });
  }
}
