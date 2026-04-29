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
  }) async {
    log.d(
      '[ad][admob_rewarded][load] start placement=$placement adid=${unit.id}',
    );
    final completer = Completer<AdLoadResult<RewardedAd>>();
    RewardedAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          log.d(
            '[ad][admob_rewarded][load] loaded placement=$placement adid=${unit.id}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          }
        },
        onAdFailedToLoad: (error) {
          log.d(
            '[ad][admob_rewarded][load] failed placement=$placement adid=${unit.id} code=${error.code} reason=${error.message}',
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
          '[ad][admob_rewarded][load] timeout placement=$placement adid=${unit.id}',
        );
        return AdLoadResult.failure(
          type: type,
          adUnitId: unit.id,
          error: TimeoutException('rewarded ad load timeout'),
        );
      },
    );
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required RewardedAd ad,
    required AdEventReporter reporter,
    VoidCallback? onClosed,
  }) async {
    log.d(
      '[ad][admob_rewarded][show] start placement=${placementLabel ?? placement} adid=${ad.adUnitId}',
    );
    final completer = Completer<AdShowResult>();
    var rewardEarned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdShowedFullScreenContent: (ad) {
        log.d(
          '[ad][admob_rewarded][show] showed placement=${placementLabel ?? placement} adid=${ad.adUnitId}',
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
      },
      onAdDismissedFullScreenContent: (ad) {
        log.d(
          '[ad][admob_rewarded][show] dismissed placement=${placementLabel ?? placement} adid=${ad.adUnitId} rewardEarned=$rewardEarned',
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
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(AdShowResult.success(rewardEarned: rewardEarned));
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        log.d(
          '[ad][admob_rewarded][show] failed placement=${placementLabel ?? placement} adid=${ad.adUnitId} code=${error.code} reason=${error.message}',
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
        '[ad][admob_rewarded][income] placement=${placementLabel ?? placement} adid=${ad.adUnitId} value=$valueMicros currency=$currencyCode',
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
    await ad.show(
      onUserEarnedReward: (ad, reward) {
        rewardEarned = true;
        log.d(
          '[ad][admob_rewarded][reward] placement=${placementLabel ?? placement} adid=${ad.adUnitId} amount=${reward.amount} type=${reward.type}',
        );
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
