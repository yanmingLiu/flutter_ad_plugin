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

class AdmobRewardedAdapter implements AdTypeAdapter<RewardedAd> {
  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.rewarded;

  @override
  Future<AdLoadResult<RewardedAd>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    void Function(RewardedAd ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.d('📥 load:rewarded:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<RewardedAd>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.d('❌ timeout:rewarded:${placement.name}');
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('rewarded ad load timeout'),
          ),
        );
      }
    });

    RewardedAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          log.d('✅ loaded:rewarded:${placement.name}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            log.d('📥 late_load:rewarded:${placement.name} (cached)');
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.d('❌ failed:rewarded:${placement.name} code=${error.code}');
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
    required RewardedAd ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final placementValue = placementLabel ?? placement.name;
    log.d('🚀 show:rewarded:$placementValue');
    final completer = Completer<AdShowResult>();
    var rewardEarned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdShowedFullScreenContent: (ad) {
        log.d('✅ showed:rewarded:$placementValue');
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
        log.d('🚪 closed:rewarded:$placementValue reward=$rewardEarned');
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
          completer.complete(AdShowResult.success(rewardEarned: rewardEarned));
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        log.d('❌ show_failed:rewarded:$placementValue code=${error.code}');
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
      log.d('💰 income:rewarded:$placementValue value=$valueMicros $currencyCode');
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
    await ad.show(
      onUserEarnedReward: (ad, reward) {
        rewardEarned = true;
        log.d('🎁 reward:rewarded:$placementValue ${reward.amount} ${reward.type}');
        reporter.report(
          AdEvent(
            eventType: AdEventType.rewardEarned,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: AdSource.admob,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
          ),
        );
      },
    );
    return completer.future;
  }

  @override
  void dispose(RewardedAd ad) {
    ad.dispose();
  }
}
