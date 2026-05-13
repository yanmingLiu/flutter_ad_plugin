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
    required AdEventReporter reporter,
    void Function(AppOpenAd ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.d('📥 load:open:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<AppOpenAd>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.d('❌ timeout:open:${placement.name}');
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('open ad load timeout'),
          ),
        );
      }
    });

    AppOpenAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          log.d('✅ loaded:open:${placement.name}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            log.d('📥 late_load:open:${placement.name} (cached)');
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.d('❌ failed:open:${placement.name} code=${error.code}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
      ),
    );

    return completer.future;
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required AppOpenAd ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final placementValue = placementLabel ?? placement.name;
    log.d('🚀 show:open:$placementValue');
    final completer = Completer<AdShowResult>();
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdShowedFullScreenContent: (ad) {
        log.d('✅ showed:open:$placementValue');
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
        onAdShowed?.call();
      },
      onAdDismissedFullScreenContent: (ad) {
        log.d('🚪 closed:open:$placementValue');
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
        ad.dispose();
        onClosed?.call();
        if (!completer.isCompleted) {
          completer.complete(AdShowResult.success());
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        log.d('❌ show_failed:open:$placementValue code=${error.code}');
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
      log.d('💰 income:open:$placementValue value=$valueMicros $currencyCode');
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
