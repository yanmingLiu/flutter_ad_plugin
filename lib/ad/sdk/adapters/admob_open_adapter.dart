import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../analytics/ad_event.dart';
import '../../analytics/ad_event_reporter.dart';
import '../../core/ad_config.dart';
import '../../core/ad_enums.dart';
import '../../core/ad_models.dart';
import '../../../tools/log_tool.dart';
import '../ad_type_adapter.dart';

class AdmobOpenAdapter implements AdTypeAdapter<AppOpenAd> {
  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.open;

  @override
  Future<AdLoadResult<AppOpenAd>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
  }) async {
    log.d(
      '[ad][admob_open][load] start placement=${placement.name} adid=${unit.id}',
    );
    final completer = Completer<AdLoadResult<AppOpenAd>>();
    AppOpenAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          log.d(
            '[ad][admob_open][load] loaded placement=${placement.name} adid=${unit.id}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          }
        },
        onAdFailedToLoad: (error) {
          log.d(
            '[ad][admob_open][load] failed placement=${placement.name} adid=${unit.id} code=${error.code} reason=${error.message}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
      ),
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        log.d(
          '[ad][admob_open][load] timeout placement=${placement.name} adid=${unit.id}',
        );
        return AdLoadResult.failure(
          type: type,
          adUnitId: unit.id,
          error: TimeoutException('open ad load timeout'),
        );
      },
    );
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required AppOpenAd ad,
    required AdEventReporter reporter,
    VoidCallback? onClosed,
  }) async {
    log.d(
      '[ad][admob_open][show] start placement=${placementLabel ?? placement.name} adid=${ad.adUnitId}',
    );
    final completer = Completer<AdShowResult>();
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdShowedFullScreenContent: (ad) {
        log.d(
          '[ad][admob_open][show] showed placement=${placementLabel ?? placement.name} adid=${ad.adUnitId}',
        );
        reporter.report(
          AdEvent(
            eventType: AdEventType.showSuccess,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: AdSource.admob,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
          ),
        );
        if (!completer.isCompleted) {
          completer.complete(AdShowResult.success());
        }
      },
      onAdDismissedFullScreenContent: (ad) {
        log.d(
          '[ad][admob_open][show] dismissed placement=${placementLabel ?? placement.name} adid=${ad.adUnitId}',
        );
        reporter.report(
          AdEvent(
            eventType: AdEventType.close,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: AdSource.admob,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
          ),
        );
        onClosed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        log.d(
          '[ad][admob_open][show] failed placement=${placementLabel ?? placement.name} adid=${ad.adUnitId} code=${error.code} reason=${error.message}',
        );
        reporter.report(
          AdEvent(
            eventType: AdEventType.showFail,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: AdSource.admob,
            adUnitId: ad.adUnitId,
            errorCode: error.code,
            errorReason: error.message,
            timestamp: DateTime.now(),
          ),
        );
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(AdShowResult.failure(error));
        }
      },
    );
    ad.onPaidEvent = (ad, valueMicros, precision, currencyCode) {
      log.d(
        '[ad][admob_open][income] placement=${placementLabel ?? placement.name} adid=${ad.adUnitId} value=$valueMicros currency=$currencyCode',
      );
      reporter.report(
        AdEvent(
          eventType: AdEventType.income,
          placement: placement,
          placementLabel: placementLabel,
          adType: type,
          source: AdSource.admob,
          adUnitId: ad.adUnitId,
          revenue: valueMicros,
          currency: currencyCode,
          timestamp: DateTime.now(),
        ),
      );
    };
    reporter.report(
      AdEvent(
        eventType: AdEventType.show,
        placement: placement,
        placementLabel: placementLabel,
        adType: type,
        source: AdSource.admob,
        adUnitId: ad.adUnitId,
        timestamp: DateTime.now(),
      ),
    );
    await ad.show();
    return completer.future;
  }

  @override
  void dispose(AppOpenAd ad) {
    ad.dispose();
  }
}
