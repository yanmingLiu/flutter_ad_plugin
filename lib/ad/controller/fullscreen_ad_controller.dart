import 'dart:async';

import '../analytics/ad_event.dart';
import '../analytics/ad_event_reporter.dart';
import '../config/ad_config_repository.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../core/placement_capabilities.dart';
import '../sdk/ad_adapter_registry.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
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

  PlacementAdSlot? getSlot(PlacementType placement) => _slots[placement];

  bool hasAvailableAd(PlacementType placement) {
    return _slots[placement]?.hasAd ?? false;
  }

  Future<bool> preload(PlacementType placement) async {
    final current = _slots[placement];
    if (current?.isLoading == true) {
      log.d(
        '[ad][fullscreen][preload] skip_loading placement=$placement',
      );
      return false;
    }
    if (current?.hasAd == true) {
      log.d(
        '[ad][fullscreen][preload] skip_has_cache placement=$placement adid=${current?.adUnitId ?? ''}',
      );
      return true;
    }

    log.d('[ad][fullscreen][preload] start placement=$placement');

    _slots[placement] = PlacementAdSlot(placement: placement, isLoading: true);

    final config = await configRepository.getConfig();
    final timeout = Duration(seconds: config.loadTimeoutSeconds);
    final deadline = DateTime.now().add(timeout);
    final units =
        config
            .getUnits(placement)
            .where((unit) => unit.isValid)
            .where((unit) => PlacementCapabilities.supports(
                  config: config,
                  placement: placement,
                  type: unit.type,
                ))
            .toList()
          ..sort((a, b) => b.weight.compareTo(a.weight));

    log.d(
      '[ad][fullscreen][preload] candidates placement=$placement count=${units.length}',
    );

    Object? lastError;
    for (final unit in units) {
      final remain = deadline.difference(DateTime.now());
      if (remain <= Duration.zero) {
        lastError = TimeoutException(
          '$placement placement preload timeout',
        );
        log.d(
          '[ad][fullscreen][preload] placement_timeout placement=$placement',
        );
        break;
      }

      log.d(
        '[ad][fullscreen][preload] try placement=$placement type=${unit.type.name} adid=${unit.id} weight=${unit.weight}',
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
          '[ad][fullscreen][preload] success placement=$placement type=${unit.type.name} adid=${unit.id}',
        );
        return true;
      }

      lastError = result.error;
      log.d(
        '[ad][fullscreen][preload] fail placement=$placement type=${unit.type.name} adid=${unit.id} error=$lastError',
      );
      reporter.report(
        AdEvent(
          eventType: AdEventType.loadFailed,
          placement: placement,
          adType: unit.type,
          source: unit.source,
          adUnitId: unit.id,
          errorCode: _extractErrorCode(lastError),
          errorReason: _extractErrorReason(lastError),
          timestamp: DateTime.now(),
        ),
      );
    }

    _slots[placement] = PlacementAdSlot(
      placement: placement,
      lastError: lastError,
    );
    log.d(
      '[ad][fullscreen][preload] exhausted placement=$placement error=$lastError',
    );
    return false;
  }

  Future<AdShowResult> show(
    PlacementType placement, {
    String? placementLabel,
  }) async {
    final slot = _slots[placement];
    if (slot?.ad == null ||
        slot?.loadedType == null ||
        slot?.loadedSource == null) {
      log.d(
        '[ad][fullscreen][show] no_cached_slot placement=${placementLabel ?? placement}',
      );
      return AdShowResult.failure('No cached ad for $placement');
    }

    final currentSlot = slot!;
    final loadedSource = currentSlot.loadedSource!;
    final loadedType = currentSlot.loadedType!;
    log.d(
      '[ad][fullscreen][show] use_cache placement=${placementLabel ?? placement} source=${loadedSource.name} type=${loadedType.name} adid=${currentSlot.adUnitId ?? ''}',
    );
    final adapter = adapterRegistry.get(loadedSource, loadedType);
    final result = await adapter.show(
      placement: placement,
      placementLabel: placementLabel,
      ad: currentSlot.ad!,
      reporter: reporter,
      onClosed: () {
        log.d(
          '[ad][fullscreen][show] on_closed placement=${placementLabel ?? placement} source=${loadedSource.name} type=${loadedType.name} adid=${currentSlot.adUnitId ?? ''}',
        );
        clear(placement);
        preload(placement);
      },
    );
    if (!result.shown) {
      log.d(
        '[ad][fullscreen][show] failed placement=${placementLabel ?? placement} source=${loadedSource.name} type=${loadedType.name} error=${result.error}',
      );
      clear(placement);
      preload(placement);
    } else {
      log.d(
        '[ad][fullscreen][show] success placement=${placementLabel ?? placement} source=${loadedSource.name} type=${loadedType.name}',
      );
    }
    return result;
  }

  void clear(PlacementType placement) {
    final slot = _slots[placement];
    if (slot != null) {
      log.d(
        '[ad][fullscreen][clear] placement=$placement source=${slot.loadedSource?.name ?? ''} type=${slot.loadedType?.name ?? ''} adid=${slot.adUnitId ?? ''}',
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
    _slots.remove(placement);
  }

  void dispose() {
    for (final placement in _slots.keys.toList()) {
      clear(placement);
    }
  }

  int? _extractErrorCode(Object? error) {
    if (error is LoadAdError) {
      return error.code;
    }
    return null;
  }

  String _extractErrorReason(Object? error) {
    if (error is LoadAdError) {
      return error.message;
    }
    return '$error';
  }
}
