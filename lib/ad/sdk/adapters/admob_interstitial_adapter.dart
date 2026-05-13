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

class AdmobInterstitialAdapter implements AdTypeAdapter<InterstitialAd> {
  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.interstitial;

  @override
  Future<AdLoadResult<InterstitialAd>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    void Function(InterstitialAd ad, AdType type, String adUnitId)?
    onLateAdLoaded,
  }) async {
    log.d('📥 load:interstitial:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<InterstitialAd>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.d('❌ timeout:interstitial:${placement.name}');
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('interstitial ad load timeout'),
          ),
        );
      }
    });

    InterstitialAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          log.d('✅ loaded:interstitial:${placement.name}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            log.d('📥 late_load:interstitial:${placement.name} (cached)');
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.d('❌ failed:interstitial:${placement.name} code=${error.code}');
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
    required InterstitialAd ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final placementValue = placementLabel ?? placement.name;
    log.d('🚀 show:interstitial:$placementValue');
    final completer = Completer<AdShowResult>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (ad) {
        log.d('✅ showed:interstitial:$placementValue');
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
        log.d('🚪 closed:interstitial:$placementValue');
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
        log.d('❌ show_failed:interstitial:$placementValue code=${error.code}');
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
      log.d('💰 income:interstitial:$placementValue value=$valueMicros $currencyCode');
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
  void dispose(InterstitialAd ad) {
    ad.dispose();
  }
}
